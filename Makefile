# My CRM Makefile
# Provides easy commands for testing, building, and development

.PHONY: help test test-all test-quick test-group test-dragdrop test-operations test-database test-contactbar test-basic build clean install-hooks

# Default target
help:
	@echo "My CRM Development Commands"
	@echo "=========================="
	@echo ""
	@echo "Testing Commands:"
	@echo "  test          Run all tests"
	@echo "  test-quick    Run quick validation tests only"
	@echo "  test-group    Run group management tests"
	@echo "  test-dragdrop Run drag & drop tests"
	@echo "  test-operations Run group operations tests"
	@echo "  test-database Run database tests"
	@echo "  test-contactbar Run contact bar to groups bar tests"
	@echo "  test-basic    Run basic model tests"
	@echo ""
	@echo "Build Commands:"
	@echo "  build         Build the application"
	@echo "  build-test    Build and test the application"
	@echo "  clean         Clean build artifacts"
	@echo ""
	@echo "Development Commands:"
	@echo "  install-hooks Install git hooks for pre-commit testing"
	@echo "  watch-tests   Watch for file changes and run tests automatically"
	@echo ""

# Testing commands
test: test-all

test-all:
	@echo "🧪 Running all tests..."
	@./Tests/run_tests.sh all

test-quick:
	@echo "⚡ Running quick tests..."
	@swift test --filter SimpleXCTests

test-group:
	@echo "👥 Running group management tests..."
	@./Tests/run_tests.sh group

test-dragdrop:
	@echo "🖱️ Running drag & drop tests..."
	@./Tests/run_tests.sh dragdrop

test-operations:
	@echo "⚙️ Running group operations tests..."
	@./Tests/run_tests.sh operations

test-database:
	@echo "🗄️ Running database tests..."
	@./Tests/run_tests.sh database

test-contactbar:
	@echo "📞 Running contact bar to groups bar tests..."
	@./Tests/run_tests.sh contactbar

test-basic:
	@echo "🔧 Running basic model tests..."
	@./Tests/run_tests.sh basic

# Build commands
build:
	@echo "🔨 Building application..."
	@swift build

build-test: test build
	@echo "✅ Build and test completed successfully!"

clean:
	@echo "🧹 Cleaning build artifacts..."
	@swift package clean
	@rm -rf .build
	@rm -rf build
	@rm -rf test_results

# Development commands
install-hooks:
	@echo "🔗 Installing git hooks..."
	@chmod +x .git/hooks/pre-commit
	@echo "✅ Pre-commit hook installed"

watch-tests:
	@echo "👀 Watching for file changes and running tests..."
	@echo "Press Ctrl+C to stop"
	@fswatch -o Core/ UI/ Tests/ | xargs -n1 -I{} make test-quick

# CI/CD commands
ci-test:
	@echo "🤖 Running CI test suite..."
	@swift test --enable-code-coverage
	@./Tests/run_tests.sh all

ci-build:
	@echo "🤖 Running CI build..."
	@swift build
	@./build_app.sh "CI Build"

# Performance testing
perf-test:
	@echo "⚡ Running performance tests..."
	@swift test --filter GroupDatabaseTests
	@echo "Performance test results:"
	@grep -E "(Created.*groups in|Added.*members in)" test_results/test_run_*.log | tail -2

# Test coverage
coverage:
	@echo "📊 Generating test coverage report..."
	@swift test --enable-code-coverage
	@xcrun llvm-cov show .build/debug/MyCRMPackageTests.xctest/Contents/MacOS/MyCRMPackageTests -instr-profile .build/debug/codecov/default.profdata

# Debug commands
debug-test:
	@echo "🐛 Running tests with debug output..."
	@swift test --verbose

debug-build:
	@echo "🐛 Building with debug symbols..."
	@swift build --configuration debug

# Release commands
release-build:
	@echo "🚀 Building release version..."
	@swift build --configuration release

release-test:
	@echo "🚀 Testing release build..."
	@swift test --configuration release
