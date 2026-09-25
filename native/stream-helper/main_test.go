package main

import (
	"bytes"
	"context"
	"encoding/json"
	"fmt"
	"io"
	"net"
	"os"
	"os/exec"
	"strings"
	"sync"
	"testing"
	"time"

	"github.com/bufbuild/protocompile"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/dynamicpb"
)

type fixtureService interface{ streamFixture() }
type fixture struct {
	requestType  protoreflect.MessageDescriptor
	responseType protoreflect.MessageDescriptor
	mu           sync.Mutex
	seen         []string
	keys         []string
	mode         string
	done         chan struct{}
}

func (*fixture) streamFixture() {}

func newFixture(t *testing.T, mode string) (*fixture, string, func()) {
	t.Helper()
	compiler := protocompile.Compiler{Resolver: protocompile.WithStandardImports(&protocompile.SourceResolver{Accessor: func(path string) (io.ReadCloser, error) {
		if path == "stream_list.proto" {
			return io.NopCloser(strings.NewReader(schema)), nil
		}
		return nil, os.ErrNotExist
	}})}
	files, err := compiler.Compile(context.Background(), "stream_list.proto")
	if err != nil {
		t.Fatal(err)
	}
	f := &fixture{requestType: files[0].Messages().ByName("LiveChatMessageListRequest"), responseType: files[0].Messages().ByName("LiveChatMessageListResponse"), mode: mode, done: make(chan struct{}, 1)}
	listener, err := net.Listen("tcp", "127.0.0.1:0")
	if err != nil {
		t.Fatal(err)
	}
	server := grpc.NewServer()
	server.RegisterService(&grpc.ServiceDesc{
		ServiceName: "youtube.api.v3.V3DataLiveChatMessageService",
		HandlerType: (*fixtureService)(nil),
		Streams:     []grpc.StreamDesc{{StreamName: "StreamList", ServerStreams: true, Handler: func(srv any, stream grpc.ServerStream) error { return srv.(*fixture).handle(stream) }}},
	}, f)
	go server.Serve(listener)
	return f, listener.Addr().String(), func() { server.Stop(); listener.Close() }
}

func (f *fixture) handle(stream grpc.ServerStream) error {
	request := dynamicpb.NewMessage(f.requestType)
	if err := stream.RecvMsg(request); err != nil {
		return err
	}
	md, _ := metadata.FromIncomingContext(stream.Context())
	token := request.Get(f.requestType.Fields().ByName("page_token")).String()
	f.mu.Lock()
	f.seen = append(f.seen, token)
	f.keys = append(f.keys, md.Get("authorization")...)
	f.keys = append(f.keys, md.Get("x-goog-api-key")...)
	f.mu.Unlock()
	if f.mode == "error" {
		return status.Error(codes.ResourceExhausted, "private server detail")
	}
	if f.mode == "wait" {
		<-stream.Context().Done()
		f.done <- struct{}{}
		return stream.Context().Err()
	}
	for _, pair := range []struct{ next, kind string }{{"cursor-1", "TEXT_MESSAGE_EVENT"}, {"cursor-2", "SUPER_CHAT_EVENT"}} {
		if f.mode == "spaced" {
			select {
			case <-time.After(900 * time.Millisecond):
			case <-stream.Context().Done():
				return stream.Context().Err()
			}
		}
		response := dynamicpb.NewMessage(f.responseType)
		payload := map[string]any{"nextPageToken": pair.next, "items": []any{map[string]any{
			"id": pair.next, "snippet": map[string]any{"type": pair.kind, "liveChatId": "chat", "displayMessage": strings.Repeat("x", 4090) + "hé😀", "superChatDetails": map[string]any{"amountMicros": "18446744073709551615"}},
		}}}
		encoded, _ := json.Marshal(payload)
		if err := protojson.Unmarshal(encoded, response); err != nil {
			return err
		}
		if err := stream.SendMsg(response); err != nil {
			return err
		}
	}
	if f.mode == "wait_after_pages" {
		<-stream.Context().Done()
		f.done <- struct{}{}
		return stream.Context().Err()
	}
	return nil
}

func TestFixtureServer(t *testing.T) {
	if os.Getenv("RTSL_FIXTURE_SERVER") != "1" {
		return
	}
	_, endpoint, closeFixture := newFixture(t, "wait_after_pages")
	defer closeFixture()
	fmt.Println("RTSL_ENDPOINT=" + endpoint)
	_ = os.Stdout.Sync()
	time.Sleep(30 * time.Second)
}

// Launched only by the Redot pipe-boundary harness. The first JSON frame is
// exactly 1 MiB before its newline; the second frame tests aggregate draining.
func TestFrameEmitterProcess(t *testing.T) {
	if os.Getenv("RTSL_FRAME_EMITTER") != "1" {
		return
	}
	prefix := `{"protocol":"RTSL/1","kind":"page","page":{"items":[],"kind":"`
	suffix := `"}}`
	_, _ = io.WriteString(os.Stdout, prefix+strings.Repeat("x", maxFrameBytes-len(prefix)-len(suffix))+suffix+"\n")
	_, _ = io.WriteString(os.Stdout, `{"protocol":"RTSL/1","kind":"page","page":{"items":[],"nextPageToken":"second"}}`+"\n")
	_ = os.Stdout.Sync()
	time.Sleep(30 * time.Second)
}

func requestWire(endpoint, token, auth string) string {
	value, _ := json.Marshal(request{Protocol: protocol, AuthKind: auth, Credential: token, LiveChatID: "chat", Endpoint: endpoint})
	return string(value) + "\n"
}

func frames(t *testing.T, output string) []frame {
	t.Helper()
	var result []frame
	for _, line := range strings.Split(strings.TrimSpace(output), "\n") {
		var value frame
		if err := json.Unmarshal([]byte(line), &value); err != nil {
			t.Fatal(err, output)
		}
		result = append(result, value)
	}
	return result
}

func TestMultipleResponsesAndMapping(t *testing.T) {
	f, endpoint, closeFixture := newFixture(t, "pages")
	defer closeFixture()
	var output bytes.Buffer
	if err := run(strings.NewReader(requestWire(endpoint, "test-oauth-token", "oauth")), &output, []string{"--test-loopback"}); err != nil {
		t.Fatal(err)
	}
	got := frames(t, output.String())
	if len(got) != 3 || got[0].Kind != "page" || got[1].Kind != "page" || got[2].Kind != "eof" {
		t.Fatalf("wrong stream frames: %+v", got)
	}
	if got[0].Page["nextPageToken"] != "cursor-1" || got[1].Page["nextPageToken"] != "cursor-2" {
		t.Fatal("cursor not preserved")
	}
	first := got[0].Page["items"].([]any)[0].(map[string]any)["snippet"].(map[string]any)
	second := got[1].Page["items"].([]any)[0].(map[string]any)["snippet"].(map[string]any)
	if first["type"] != "textMessageEvent" || second["type"] != "superChatEvent" {
		t.Fatal("enum mapping failed")
	}
	if second["superChatDetails"].(map[string]any)["amountMicros"] != "18446744073709551615" {
		t.Fatal("uint64 precision lost")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.keys) != 1 || f.keys[0] != "Bearer test-oauth-token" {
		t.Fatal("OAuth metadata wrong")
	}
	if strings.Contains(output.String(), "test-oauth-token") {
		t.Fatal("secret leaked to output")
	}
}

func TestHelperProcessResumeAndAPIKey(t *testing.T) {
	f, endpoint, closeFixture := newFixture(t, "pages")
	defer closeFixture()
	value := request{Protocol: protocol, AuthKind: "api_key", Credential: "private-api-key", LiveChatID: "chat", PageToken: "resume-here", Endpoint: endpoint}
	encoded, _ := json.Marshal(value)
	cmd := exec.Command(os.Args[0], "-test.run=TestChildHelperProcess")
	cmd.Env = append(os.Environ(), "RTSL_CHILD_HELPER=1")
	cmd.Stdin = strings.NewReader(string(encoded) + "\n")
	output, err := cmd.CombinedOutput()
	if err != nil {
		t.Fatalf("helper process failed: %v %s", err, output)
	}
	got := frames(t, string(output))
	if len(got) != 3 || got[1].Page["nextPageToken"] != "cursor-2" {
		t.Fatal("helper process did not stream multiple responses")
	}
	f.mu.Lock()
	defer f.mu.Unlock()
	if len(f.seen) != 1 || f.seen[0] != "resume-here" || len(f.keys) != 1 || f.keys[0] != "private-api-key" {
		t.Fatal("resume/API-key metadata wrong")
	}
	if strings.Contains(string(output), "private-api-key") {
		t.Fatal("secret leaked")
	}
}

func TestChildHelperProcess(t *testing.T) {
	if os.Getenv("RTSL_CHILD_HELPER") != "1" {
		return
	}
	if err := run(os.Stdin, os.Stdout, []string{"--test-loopback"}); err != nil {
		os.Exit(1)
	}
	os.Exit(0)
}

func TestErrorIsSanitized(t *testing.T) {
	_, endpoint, closeFixture := newFixture(t, "error")
	defer closeFixture()
	var output bytes.Buffer
	if err := run(strings.NewReader(requestWire(endpoint, "secret", "oauth")), &output, []string{"--test-loopback"}); err == nil {
		t.Fatal("expected status failure")
	}
	got := frames(t, output.String())
	if len(got) != 1 || got[0].Kind != "error" || got[0].Code != "resource_exhausted" || strings.Contains(output.String(), "private") || strings.Contains(output.String(), "secret") {
		t.Fatalf("unsanitized status: %+v", got)
	}
}

func TestPreconditionReasonAllowlist(t *testing.T) {
	for _, tc := range []struct{ message, want string }{
		{"LIVE_CHAT_DISABLED", "LIVE_CHAT_DISABLED"},
		{"LIVE_CHAT_ENDED", "LIVE_CHAT_ENDED"},
		{"a private server detail", ""},
	} {
		if got := safeReason(status.Error(codes.FailedPrecondition, tc.message)); got != tc.want {
			t.Fatalf("got %q, want %q", got, tc.want)
		}
	}
	if safeReason(status.Error(codes.ResourceExhausted, "LIVE_CHAT_ENDED")) != "" {
		t.Fatal("non-precondition reason leaked")
	}
}

func TestCanceledStatusSpelling(t *testing.T) {
	if got := safeStatus(status.Error(codes.Canceled, "private detail")); got != "canceled" { t.Fatalf("canceled code mismatch: %q", got) }
}

func TestLimitsAndProductionEndpoint(t *testing.T) {
	for _, tc := range []string{requestWire("attacker.example:443", "secret", "oauth"), strings.Repeat("A", maxRequestBytes+1) + "\n", requestWire("127.0.0.1:1234", "secret", "oauth")} {
		var output bytes.Buffer
		if err := run(strings.NewReader(tc), &output, nil); err == nil {
			t.Fatal("invalid request accepted")
		}
		if strings.Contains(output.String(), "secret") {
			t.Fatal("secret leaked")
		}
	}
	if isLoopbackEndpoint("localhost:443") != true || isLoopbackEndpoint("127.0.0.2:443") || isLoopbackEndpoint("localhost:0") {
		t.Fatal("loopback guard failed")
	}
}

func TestCancellationStopsRPC(t *testing.T) {
	f, endpoint, closeFixture := newFixture(t, "wait")
	defer closeFixture()
	cmd := exec.Command(os.Args[0], "-test.run=TestChildHelperProcess")
	cmd.Env = append(os.Environ(), "RTSL_CHILD_HELPER=1")
	cmd.Stdin = strings.NewReader(requestWire(endpoint, "secret", "oauth"))
	var output bytes.Buffer
	cmd.Stdout = &output
	if err := cmd.Start(); err != nil {
		t.Fatal(err)
	}
	deadline := time.Now().Add(5 * time.Second)
	for {
		f.mu.Lock()
		seen := len(f.seen)
		f.mu.Unlock()
		if seen > 0 {
			break
		}
		if time.Now().After(deadline) {
			cmd.Process.Kill()
			t.Fatal("RPC did not start")
		}
		time.Sleep(10 * time.Millisecond)
	}
	if err := cmd.Process.Kill(); err != nil {
		t.Fatal(err)
	}
	_ = cmd.Wait()
	select {
	case <-f.done:
	case <-time.After(5 * time.Second):
		t.Fatal("killed helper did not cancel server RPC")
	}
}

func TestIdleWatchdogResetsAndQuietStreamTimesOut(t *testing.T) {
	_, endpoint, closeFixture := newFixture(t, "spaced")
	defer closeFixture()
	req := request{Protocol: protocol, AuthKind: "oauth", Credential: "test-token", LiveChatID: "chat", Endpoint: endpoint, IdleTimeoutMS: 1500}
	wire, _ := json.Marshal(req)
	var output bytes.Buffer
	started := time.Now()
	if err := run(strings.NewReader(string(wire)+"\n"), &output, []string{"--test-loopback"}); err != nil {
		t.Fatal(err)
	}
	if time.Since(started) < 1500*time.Millisecond || len(frames(t, output.String())) != 3 {
		t.Fatal("watchdog did not reset after first page")
	}
	_, quietEndpoint, closeQuiet := newFixture(t, "wait")
	defer closeQuiet()
	quietReq := request{Protocol: protocol, AuthKind: "oauth", Credential: "test-token", LiveChatID: "chat", Endpoint: quietEndpoint, IdleTimeoutMS: 1000}
	quietWire, _ := json.Marshal(quietReq)
	output.Reset()
	if err := run(strings.NewReader(string(quietWire)+"\n"), &output, []string{"--test-loopback"}); err == nil {
		t.Fatal("quiet stream had no bounded idle exit")
	}
	got := frames(t, output.String())
	if len(got) != 1 || got[0].Kind != "error" || got[0].Code != "canceled" {
		t.Fatalf("quiet stream exit was not explicit: %+v", got)
	}
}

func TestEnumAndOneofMapping(t *testing.T) {
	f, _, closeFixture := newFixture(t, "pages")
	defer closeFixture()
	types := []struct {
		number int
		name   string
	}{
		{0, "invalidType"}, {1, "textMessageEvent"}, {2, "tombstone"}, {3, "fanFundingEvent"},
		{4, "chatEndedEvent"}, {5, "sponsorOnlyModeStartedEvent"}, {6, "sponsorOnlyModeEndedEvent"},
		{7, "newSponsorEvent"}, {10, "userBannedEvent"}, {15, "superChatEvent"},
		{16, "superStickerEvent"}, {17, "memberMilestoneChatEvent"}, {18, "membershipGiftingEvent"},
		{19, "giftMembershipReceivedEvent"}, {20, "pollEvent"}, {21, "giftEvent"},
	}
	for _, tc := range types {
		payload := map[string]any{"items": []any{map[string]any{"id": "event", "snippet": map[string]any{"type": tc.number}}}}
		wire, _ := json.Marshal(payload)
		message := dynamicpb.NewMessage(f.responseType)
		if err := protojson.Unmarshal(wire, message); err != nil {
			t.Fatal(err)
		}
		mapped, err := mapResponse(message)
		if err != nil {
			t.Fatal(err)
		}
		got := mapped["items"].([]any)[0].(map[string]any)["snippet"].(map[string]any)["type"]
		if got != tc.name {
			t.Fatalf("enum %d mapped to %v, want %s", tc.number, got, tc.name)
		}
	}
	unknown := dynamicpb.NewMessage(f.responseType)
	if err := protojson.Unmarshal([]byte(`{"items":[{"id":"future","snippet":{"type":99}}]}`), unknown); err != nil {
		t.Fatal(err)
	}
	if got, _ := mapResponse(unknown); got["items"].([]any)[0].(map[string]any)["snippet"].(map[string]any)["type"] != float64(99) {
		t.Fatal("unknown enum value was lost")
	}
	payload := `{"activePollItem":{"id":"poll","snippet":{"type":20,"pollDetails":{"status":2,"metadata":{"questionText":"Q","options":[{"optionText":"A","tally":"4"},{"optionText":"B","tally":"5"}]}}}},"items":[{"id":"gift","snippet":{"type":21,"giftDetails":{"giftName":"Heart","giftDuration":"1.25s","jewelsAmount":7,"comboCount":2}}},{"id":"sticker","snippet":{"type":16,"superStickerDetails":{"superStickerMetadata":{"altTextLanguage":"en"}}}}]}`
	message := dynamicpb.NewMessage(f.responseType)
	if err := protojson.Unmarshal([]byte(payload), message); err != nil {
		t.Fatal(err)
	}
	mapped, err := mapResponse(message)
	if err != nil {
		t.Fatal(err)
	}
	if len(mapped["items"].([]any)) != 2 || mapped["activePollItem"].(map[string]any)["id"] != "poll" {
		t.Fatal("active poll lost or duplicated")
	}
	poll := mapped["activePollItem"].(map[string]any)["snippet"].(map[string]any)["pollDetails"].(map[string]any)
	if poll["metadata"].(map[string]any)["status"] != "closed" || poll["metadata"].(map[string]any)["options"].([]any)[0].(map[string]any)["optionText"] != "A" {
		t.Fatal("poll status/order mapping failed")
	}
	items := mapped["items"].([]any)
	metadata := items[0].(map[string]any)["snippet"].(map[string]any)["giftEventDetails"].(map[string]any)["giftMetadata"].(map[string]any)
	duration := metadata["giftDuration"].(map[string]any)
	if duration["seconds"] != "1" || duration["nanos"] != int64(250000000) && duration["nanos"] != float64(250000000) {
		t.Fatal("gift duration mapping failed")
	}
	sticker := items[1].(map[string]any)["snippet"].(map[string]any)["superStickerDetails"].(map[string]any)["superStickerMetadata"].(map[string]any)
	if sticker["language"] != "en" {
		t.Fatal("sticker language mapping failed")
	}
}

func TestUint64BoundariesAndOffline(t *testing.T) {
	f, _, closeFixture := newFixture(t, "pages")
	defer closeFixture()
	for _, amount := range []string{"9223372036854775807", "9223372036854775808", "18446744073709551615"} {
		payload := `{"offlineAt":"2026-09-24T00:00:00Z","items":[{"id":"paid","snippet":{"type":15,"superChatDetails":{"amountMicros":"` + amount + `"}}},{"id":"ban","snippet":{"type":10,"userBannedDetails":{"banType":2,"banDurationSeconds":"` + amount + `"}}}]}`
		message := dynamicpb.NewMessage(f.responseType)
		if err := protojson.Unmarshal([]byte(payload), message); err != nil {
			t.Fatal(err)
		}
		mapped, err := mapResponse(message)
		if err != nil {
			t.Fatal(err)
		}
		items := mapped["items"].([]any)
		paid := items[0].(map[string]any)["snippet"].(map[string]any)["superChatDetails"].(map[string]any)
		ban := items[1].(map[string]any)["snippet"].(map[string]any)["userBannedDetails"].(map[string]any)
		if paid["amountMicros"] != amount || ban["banDurationSeconds"] != amount || ban["banType"] != "temporary" || mapped["offlineAt"] == "" {
			t.Fatalf("uint64/offline mapping failed: %s", amount)
		}
	}
}

func TestDurationFullRange(t *testing.T) {
	for _, tc := range []struct {
		wire, seconds string
		nanos         int64
	}{
		{"1.25s", "1", 250000000},
		{"-1.25s", "-1", -250000000},
		{"-0.5s", "0", -500000000},
		{"10000000000s", "10000000000", 0},
		{"315576000000.000000001s", "315576000000", 1},
	} {
		got := durationMap(tc.wire)
		if got["seconds"] != tc.seconds || got["nanos"] != tc.nanos {
			t.Fatalf("duration %s: %+v", tc.wire, got)
		}
	}
}
