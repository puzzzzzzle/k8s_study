package main

import (
	"context"
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"path/filepath"
	"strings"
	"time"

	"github.com/grpc-ecosystem/go-grpc-prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
	"google.golang.org/grpc"
	"google.golang.org/grpc/health"
	healthpb "google.golang.org/grpc/health/grpc_health_v1"
	"google.golang.org/grpc/reflection"

	pb "go-grpc-svc/pb"
)

const (
	defaultGRPCPort    = "50051"
	defaultMetricsPort = "9090"
	defaultConfigDir   = "/shared-config"
)

type server struct {
	pb.UnimplementedConfigServiceServer
	configDir string
}

func (s *server) Ping(ctx context.Context, req *pb.PingRequest) (*pb.PingResponse, error) {
	return &pb.PingResponse{
		Message: "pong",
		Time:    time.Now().UTC().Format(time.RFC3339),
	}, nil
}

func (s *server) GetConfig(ctx context.Context, req *pb.GetConfigRequest) (*pb.GetConfigResponse, error) {
	filename := req.GetFilename()
	if filename == "" {
		return &pb.GetConfigResponse{
			Success: false,
			Error:   "filename is required",
		}, nil
	}

	// 安全检查：防止路径遍历
	clean := filepath.Clean(filename)
	if strings.Contains(clean, "..") || filepath.IsAbs(clean) {
		return &pb.GetConfigResponse{
			Success: false,
			Error:   "invalid filename: path traversal not allowed",
		}, nil
	}

	fullPath := filepath.Join(s.configDir, clean)
	data, err := os.ReadFile(fullPath)
	if err != nil {
		if os.IsNotExist(err) {
			return &pb.GetConfigResponse{
				Success: false,
				Error:   fmt.Sprintf("config file not found: %s", filename),
			}, nil
		}
		return &pb.GetConfigResponse{
			Success: false,
			Error:   fmt.Sprintf("failed to read config file: %v", err),
		}, nil
	}

	return &pb.GetConfigResponse{
		Success: true,
		Content: string(data),
	}, nil
}

func (s *server) ListConfigs(ctx context.Context, req *pb.ListConfigsRequest) (*pb.ListConfigsResponse, error) {
	entries, err := os.ReadDir(s.configDir)
	if err != nil {
		return &pb.ListConfigsResponse{}, nil
	}

	var filenames []string
	for _, entry := range entries {
		if !entry.IsDir() {
			filenames = append(filenames, entry.Name())
		}
	}

	return &pb.ListConfigsResponse{
		Filenames: filenames,
	}, nil
}

func main() {
	grpcPort := os.Getenv("GRPC_PORT")
	if grpcPort == "" {
		grpcPort = defaultGRPCPort
	}

	metricsPort := os.Getenv("METRICS_PORT")
	if metricsPort == "" {
		metricsPort = defaultMetricsPort
	}

	configDir := os.Getenv("CONFIG_DIR")
	if configDir == "" {
		configDir = defaultConfigDir
	}

	// 初始化 gRPC Prometheus metrics
	grpc_prometheus.EnableHandlingTimeHistogram()

	// 创建 gRPC Server，注入 prometheus interceptor
	grpcServer := grpc.NewServer(
		grpc.UnaryInterceptor(grpc_prometheus.UnaryServerInterceptor),
		grpc.StreamInterceptor(grpc_prometheus.StreamServerInterceptor),
	)

	// 注册业务服务
	svc := &server{configDir: configDir}
	pb.RegisterConfigServiceServer(grpcServer, svc)

	// 注册健康检查
	healthServer := health.NewServer()
	healthpb.RegisterHealthServer(grpcServer, healthServer)
	healthServer.SetServingStatus("configsvc.ConfigService", healthpb.HealthCheckResponse_SERVING)

	// 初始化 prometheus metrics（注册所有已知方法）
	grpc_prometheus.Register(grpcServer)

	// 启用 gRPC 反射（grpcurl 需要）
	reflection.Register(grpcServer)

	// 启动 Prometheus metrics HTTP server
	go func() {
		mux := http.NewServeMux()
		mux.Handle("/metrics", promhttp.Handler())
		mux.HandleFunc("/healthz", func(w http.ResponseWriter, r *http.Request) {
			w.WriteHeader(http.StatusOK)
			w.Write([]byte("ok"))
		})
		log.Printf("metrics server listening on :%s", metricsPort)
		if err := http.ListenAndServe(":"+metricsPort, mux); err != nil {
			log.Fatalf("metrics server error: %v", err)
		}
	}()

	// 启动 gRPC server
	lis, err := net.Listen("tcp", ":"+grpcPort)
	if err != nil {
		log.Fatalf("failed to listen: %v", err)
	}

	log.Printf("go-grpc-svc gRPC listening on :%s (config dir: %s)", grpcPort, configDir)
	if err := grpcServer.Serve(lis); err != nil {
		log.Fatalf("failed to serve: %v", err)
	}
}
