// redot-tuber-stream-helper implements the documented YouTube server-streaming
// RPC. Its only secret input is one bounded JSON line on private stdin.
package main

import (
	"bufio"
	"context"
	"crypto/tls"
	_ "embed"
	"encoding/json"
	"errors"
	"io"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/bufbuild/protocompile"
	"google.golang.org/grpc"
	"google.golang.org/grpc/codes"
	"google.golang.org/grpc/credentials"
	"google.golang.org/grpc/credentials/insecure"
	"google.golang.org/grpc/metadata"
	"google.golang.org/grpc/status"
	"google.golang.org/protobuf/encoding/protojson"
	"google.golang.org/protobuf/reflect/protoreflect"
	"google.golang.org/protobuf/types/dynamicpb"
)

//go:embed stream_list.proto
var schema string

const (
	protocol           = "RTSL/1"
	productionEndpoint = "youtube.googleapis.com:443"
	rpcMethod          = "/youtube.api.v3.V3DataLiveChatMessageService/StreamList"
	maxRequestBytes    = 16 * 1024
	maxFrameBytes      = 1024 * 1024
)

type request struct {
	Protocol      string `json:"protocol"`
	AuthKind      string `json:"auth_kind"`
	Credential    string `json:"credential"`
	LiveChatID    string `json:"live_chat_id"`
	PageToken     string `json:"page_token"`
	Endpoint      string `json:"endpoint,omitempty"`
	IdleTimeoutMS int    `json:"idle_timeout_ms,omitempty"`
}

type frame struct {
	Protocol string         `json:"protocol"`
	Kind     string         `json:"kind"`
	Page     map[string]any `json:"page,omitempty"`
	Code     string         `json:"code,omitempty"`
	Reason   string         `json:"reason,omitempty"`
}

func main() {
	// Never print the raw error: gRPC status descriptions/trailers can contain
	// server-controlled text, and input holds an OAuth token or API key.
	if err := run(os.Stdin, os.Stdout, os.Args[1:]); err != nil {
		os.Exit(1)
	}
}

func run(input io.Reader, output io.Writer, args []string) error {
	testMode := len(args) == 1 && args[0] == "--test-loopback"
	if len(args) > 0 && !testMode {
		return errors.New("invalid arguments")
	}
	writer := bufio.NewWriter(output)
	emit := func(value frame) error {
		value.Protocol = protocol
		bytes, err := json.Marshal(value)
		if err != nil || len(bytes) > maxFrameBytes {
			return errors.New("output limit")
		}
		if _, err = writer.Write(append(bytes, '\n')); err != nil {
			return err
		}
		return writer.Flush()
	}
	reader := bufio.NewReader(io.LimitReader(input, maxRequestBytes+1))
	line, err := reader.ReadBytes('\n')
	if err != nil || len(line) > maxRequestBytes {
		_ = emit(frame{Kind: "error", Code: "protocol_error"})
		return errors.New("input limit")
	}
	var req request
	if err = json.Unmarshal(line, &req); err != nil || req.Protocol != protocol || len(req.LiveChatID) == 0 || len(req.LiveChatID) > 512 || len(req.PageToken) > 4096 || len(req.Credential) == 0 || len(req.Credential) > 8192 || (req.AuthKind != "oauth" && req.AuthKind != "api_key") {
		_ = emit(frame{Kind: "error", Code: "protocol_error"})
		return errors.New("invalid input")
	}
	endpoint := productionEndpoint
	transport := grpc.WithTransportCredentials(credentials.NewTLS(&tls.Config{MinVersion: tls.VersionTLS12, ServerName: "youtube.googleapis.com"}))
	if req.Endpoint != "" {
		if !testMode || !isLoopbackEndpoint(req.Endpoint) {
			_ = emit(frame{Kind: "error", Code: "protocol_error"})
			return errors.New("invalid endpoint")
		}
		endpoint = req.Endpoint
		transport = grpc.WithTransportCredentials(insecure.NewCredentials())
	}
	compiler := protocompile.Compiler{Resolver: protocompile.WithStandardImports(&protocompile.SourceResolver{Accessor: func(path string) (io.ReadCloser, error) {
		if path == "stream_list.proto" {
			return io.NopCloser(strings.NewReader(schema)), nil
		}
		return nil, os.ErrNotExist
	}})}
	files, err := compiler.Compile(context.Background(), "stream_list.proto")
	if err != nil {
		_ = emit(frame{Kind: "error", Code: "schema_error"})
		return err
	}
	file := files[0]
	reqType := file.Messages().ByName("LiveChatMessageListRequest")
	respType := file.Messages().ByName("LiveChatMessageListResponse")
	message := dynamicpb.NewMessage(reqType)
	setString(message, "live_chat_id", req.LiveChatID)
	if req.PageToken != "" {
		setString(message, "page_token", req.PageToken)
	}
	part := message.Mutable(reqType.Fields().ByName("part")).List()
	for _, name := range []string{"id", "snippet", "authorDetails"} {
		part.Append(protoreflect.ValueOfString(name))
	}

	idle := time.Duration(req.IdleTimeoutMS) * time.Millisecond
	if idle < time.Second {
		idle = 90 * time.Second
	}
	if idle > 5*time.Minute {
		idle = 5 * time.Minute
	}
	// A quiet chat is valid. Refresh the idle watchdog after each response;
	// the 24-hour outer cap only bounds a single owned process lifetime.
	outer, outerCancel := context.WithTimeout(context.Background(), 24*time.Hour)
	defer outerCancel()
	watchCtx, cancel := context.WithCancel(outer)
	defer cancel()
	activity := make(chan struct{}, 1)
	go func() {
		timer := time.NewTimer(idle)
		defer timer.Stop()
		for {
			select {
			case <-watchCtx.Done():
				return
			case <-timer.C:
				cancel()
				return
			case <-activity:
				if !timer.Stop() {
					select {
					case <-timer.C:
					default:
					}
				}
				timer.Reset(idle)
			}
		}
	}()
	md := metadata.MD{}
	if req.AuthKind == "oauth" {
		md.Set("authorization", "Bearer "+req.Credential)
	} else {
		md.Set("x-goog-api-key", req.Credential)
	}
	req.Credential = ""
	streamCtx := metadata.NewOutgoingContext(watchCtx, md)
	conn, err := grpc.NewClient(endpoint, transport, grpc.WithDefaultCallOptions(grpc.MaxCallRecvMsgSize(maxFrameBytes)))
	if err != nil {
		_ = emit(frame{Kind: "error", Code: "unavailable"})
		return err
	}
	defer conn.Close()
	stream, err := conn.NewStream(streamCtx, &grpc.StreamDesc{ServerStreams: true}, rpcMethod)
	if err == nil {
		err = stream.SendMsg(message)
	}
	if err == nil {
		err = stream.CloseSend()
	}
	if err != nil {
		_ = emit(frame{Kind: "error", Code: safeStatus(err), Reason: safeReason(err)})
		return err
	}
	for {
		response := dynamicpb.NewMessage(respType)
		err = stream.RecvMsg(response)
		if errors.Is(err, io.EOF) {
			return emit(frame{Kind: "eof"})
		}
		if err != nil {
			_ = emit(frame{Kind: "error", Code: safeStatus(err), Reason: safeReason(err)})
			return err
		}
		select {
		case activity <- struct{}{}:
		default:
		}
		payload, mappingErr := mapResponse(response)
		if mappingErr != nil {
			_ = emit(frame{Kind: "error", Code: "mapping_error"})
			return mappingErr
		}
		if err = emit(frame{Kind: "page", Page: payload}); err != nil {
			return err
		}
		if offline, ok := payload["offlineAt"].(string); ok && offline != "" {
			return emit(frame{Kind: "terminal"})
		}
	}
}

func setString(message *dynamicpb.Message, name protoreflect.Name, value string) {
	message.Set(message.Descriptor().Fields().ByName(name), protoreflect.ValueOfString(value))
}

func isLoopbackEndpoint(value string) bool {
	host, port, ok := strings.Cut(value, ":")
	if !ok || (host != "127.0.0.1" && host != "localhost") {
		return false
	}
	n, err := strconv.Atoi(port)
	return err == nil && n > 0 && n <= 65535
}

func safeStatus(err error) string {
	code := status.Code(err)
	if code == codes.OK {
		return "unknown"
	}
	return enumToSnake(code.String())
}

func safeReason(err error) string {
	if status.Code(err) != codes.FailedPrecondition {
		return ""
	}
	message := status.Convert(err).Message()
	if strings.Contains(message, "LIVE_CHAT_DISABLED") {
		return "LIVE_CHAT_DISABLED"
	}
	if strings.Contains(message, "LIVE_CHAT_ENDED") {
		return "LIVE_CHAT_ENDED"
	}
	return ""
}

func enumToSnake(value string) string {
	var out strings.Builder
	for index, char := range value {
		if index > 0 && char >= 'A' && char <= 'Z' {
			out.WriteByte('_')
		}
		out.WriteRune(char)
	}
	return strings.ToLower(out.String())
}

func mapResponse(response *dynamicpb.Message) (map[string]any, error) {
	encoded, err := protojson.MarshalOptions{UseProtoNames: false}.Marshal(response)
	if err != nil {
		return nil, err
	}
	var result map[string]any
	if err = json.Unmarshal(encoded, &result); err != nil {
		return nil, err
	}
	items, _ := result["items"].([]any)
	for _, item := range items {
		mapItem(item)
	}
	if poll, ok := result["activePollItem"]; ok {
		mapItem(poll)
	}
	return result, nil
}

func mapItem(raw any) {
	item, ok := raw.(map[string]any)
	if !ok {
		return
	}
	snippet, ok := item["snippet"].(map[string]any)
	if !ok {
		return
	}
	if name, ok := snippet["type"].(string); ok {
		if known, found := typeNames[name]; found {
			snippet["type"] = known
		} else {
			snippet["type"] = enumToCamel(name)
		}
	}
	if banned, ok := snippet["userBannedDetails"].(map[string]any); ok {
		if kind, ok := banned["banType"].(string); ok {
			banned["banType"] = strings.ToLower(kind)
		}
	}
	if poll, ok := snippet["pollDetails"].(map[string]any); ok {
		if name, ok := poll["status"].(string); ok {
			metadata, _ := poll["metadata"].(map[string]any)
			if metadata == nil {
				metadata = map[string]any{}
				poll["metadata"] = metadata
			}
			metadata["status"] = strings.ToLower(name)
			delete(poll, "status")
		}
	}
	if gift, ok := snippet["giftDetails"].(map[string]any); ok {
		metadata := map[string]any{}
		for key, value := range gift {
			metadata[key] = value
		}
		if duration, ok := metadata["giftDuration"].(string); ok {
			metadata["giftDuration"] = durationMap(duration)
		}
		snippet["giftEventDetails"] = map[string]any{"giftMetadata": metadata}
		delete(snippet, "giftDetails")
	}
	if sticker, ok := snippet["superStickerDetails"].(map[string]any); ok {
		if details, ok := sticker["superStickerMetadata"].(map[string]any); ok {
			if language, ok := details["altTextLanguage"]; ok {
				details["language"] = language
			}
		}
	}
}

func durationMap(value string) map[string]any {
	if !strings.HasSuffix(value, "s") {
		return map[string]any{}
	}
	whole, fraction, hasFraction := strings.Cut(strings.TrimSuffix(value, "s"), ".")
	seconds, err := strconv.ParseInt(whole, 10, 64)
	if err != nil {
		return map[string]any{}
	}
	var nanos int64
	if hasFraction {
		if len(fraction) == 0 || len(fraction) > 9 {
			return map[string]any{}
		}
		for _, digit := range fraction {
			if digit < '0' || digit > '9' {
				return map[string]any{}
			}
		}
		nanos, err = strconv.ParseInt(fraction+strings.Repeat("0", 9-len(fraction)), 10, 64)
		if err != nil {
			return map[string]any{}
		}
		if strings.HasPrefix(whole, "-") {
			nanos = -nanos
		}
	}
	return map[string]any{"seconds": strconv.FormatInt(seconds, 10), "nanos": nanos}
}

func enumToCamel(value string) string {
	parts := strings.Split(strings.ToLower(value), "_")
	for i := 1; i < len(parts); i++ {
		if parts[i] != "" {
			parts[i] = strings.ToUpper(parts[i][:1]) + parts[i][1:]
		}
	}
	return strings.Join(parts, "")
}

var typeNames = map[string]string{
	"TEXT_MESSAGE_EVENT": "textMessageEvent", "TOMBSTONE": "tombstone", "FAN_FUNDING_EVENT": "fanFundingEvent",
	"CHAT_ENDED_EVENT": "chatEndedEvent", "SPONSOR_ONLY_MODE_STARTED_EVENT": "sponsorOnlyModeStartedEvent",
	"SPONSOR_ONLY_MODE_ENDED_EVENT": "sponsorOnlyModeEndedEvent", "NEW_SPONSOR_EVENT": "newSponsorEvent",
	"USER_BANNED_EVENT": "userBannedEvent", "SUPER_CHAT_EVENT": "superChatEvent", "SUPER_STICKER_EVENT": "superStickerEvent",
	"MEMBER_MILESTONE_CHAT_EVENT": "memberMilestoneChatEvent", "MEMBERSHIP_GIFTING_EVENT": "membershipGiftingEvent",
	"GIFT_MEMBERSHIP_RECEIVED_EVENT": "giftMembershipReceivedEvent", "POLL_EVENT": "pollEvent", "GIFT_EVENT": "giftEvent",
}
