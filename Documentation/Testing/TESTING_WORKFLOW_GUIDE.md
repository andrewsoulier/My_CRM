# Testing Workflow Guide

This guide explains how to integrate automated testing into your My CRM development workflow.

## 🎯 Overview

We've set up a comprehensive testing infrastructure that includes:
- **109 automated tests** covering all group management operations
- **Multiple testing workflows** for different development scenarios
- **Continuous integration** with GitHub Actions
- **Pre-commit hooks** to prevent broken code
- **Easy-to-use commands** via Makefile and VS Code tasks

## 🚀 Quick Start

### Run All Tests
```bash
# Using Makefile (recommended)
make test

# Using test script
./Tests/run_tests.sh all

# Using Swift directly
swift test
```

### Run Specific Test Suites
```bash
# Group management tests
make test-group

# Drag & drop tests
make test-dragdrop

# Contact bar to groups bar tests (your specific issue)
make test-contactbar

# Database tests
make test-database
```

## 📋 Testing Workflows

### 1. **Pre-commit Testing** (Automatic)
- **When**: Before every commit
- **What**: Runs quick validation tests
- **Purpose**: Prevents broken code from being committed

```bash
# Install pre-commit hook
make install-hooks

# Now tests run automatically before commits
git commit -m "Your changes"
```

### 2. **Development Testing** (Manual)
- **When**: During development
- **What**: Run specific tests as you work
- **Purpose**: Catch issues early

```bash
# Quick validation
make test-quick

# Test specific functionality
make test-contactbar  # For your drag & drop issue
```

### 3. **Continuous Integration** (Automatic)
- **When**: On every push/PR
- **What**: Full test suite + build verification
- **Purpose**: Ensure code quality in shared repository

### 4. **Release Testing** (Manual)
- **When**: Before releases
- **What**: Full test suite + performance tests
- **Purpose**: Ensure release quality

```bash
# Full release testing
make build-test
make perf-test
make coverage
```

## 🛠️ Available Commands

### Makefile Commands
```bash
# Testing
make test              # Run all tests
make test-quick        # Quick validation tests
make test-group        # Group management tests
make test-dragdrop     # Drag & drop tests
make test-contactbar   # Contact bar to groups bar tests
make test-database     # Database tests
make test-operations   # Group operations tests

# Building
make build             # Build application
make build-test        # Build and test
make clean             # Clean build artifacts

# Development
make install-hooks     # Install git hooks
make watch-tests       # Watch for changes and run tests
make coverage          # Generate test coverage report
make perf-test         # Run performance tests
```

### Test Script Commands
```bash
# Run specific test suites
./Tests/run_tests.sh group        # Group management tests
./Tests/run_tests.sh dragdrop     # Drag & drop tests
./Tests/run_tests.sh contactbar   # Contact bar to groups bar tests
./Tests/run_tests.sh database     # Database tests
./Tests/run_tests.sh operations   # Group operations tests
./Tests/run_tests.sh basic        # Basic model tests
./Tests/run_tests.sh all          # All tests
```

## 🎯 For Your Specific Issue

To debug the drag & drop data overwrite issue:

### 1. Run the Specific Tests
```bash
# Run the tests that check for data overwrites
make test-contactbar

# Or run the test script directly
./Tests/run_tests.sh contactbar
```

### 2. Watch for Changes
```bash
# Watch for file changes and run tests automatically
make watch-tests
```

### 3. Debug with Verbose Output
```bash
# Run tests with detailed output
swift test --filter ContactBarToGroupsBarDragDropTests --verbose
```

## 📊 Test Results and Reporting

### Test Reports
- **Location**: `test_results/` directory
- **Format**: Markdown reports with timestamps
- **Content**: Test results, performance metrics, coverage

### Performance Monitoring
```bash
# Check performance metrics
make perf-test

# View performance data
grep -E "(Created.*groups in|Added.*members in)" test_results/test_run_*.log
```

### Coverage Reports
```bash
# Generate coverage report
make coverage

# View coverage in browser
open .build/debug/codecov/default.profdata
```

## 🔧 VS Code Integration

### Tasks Available
- **Run All Tests** (Ctrl+Shift+P → "Tasks: Run Task" → "Run All Tests")
- **Run Quick Tests**
- **Run Group Management Tests**
- **Run Drag & Drop Tests**
- **Run Contact Bar to Groups Bar Tests**
- **Build Application**
- **Watch Tests** (runs continuously)

### Keyboard Shortcuts
- **Ctrl+Shift+P** → "Tasks: Run Task" → Select test task
- **Ctrl+Shift+P** → "Tasks: Run Build Task" → Build application

## 🚨 Troubleshooting

### Tests Failing
1. **Check the log file**: `test_results/test_run_*.log`
2. **Run specific test suite**: `make test-contactbar`
3. **Run with verbose output**: `swift test --verbose`

### Build Issues
1. **Clean and rebuild**: `make clean && make build`
2. **Check Swift version**: `swift --version`
3. **Update dependencies**: `swift package update`

### Pre-commit Hook Issues
1. **Reinstall hooks**: `make install-hooks`
2. **Check permissions**: `ls -la .git/hooks/pre-commit`
3. **Run manually**: `.git/hooks/pre-commit`

## 📈 Best Practices

### 1. **Run Tests Frequently**
- Before committing: `make test-quick`
- After major changes: `make test`
- Before pushing: `make build-test`

### 2. **Use Specific Tests**
- For your drag & drop issue: `make test-contactbar`
- For group operations: `make test-group`
- For database changes: `make test-database`

### 3. **Monitor Performance**
- Run performance tests: `make perf-test`
- Check coverage: `make coverage`
- Review test reports: `test_results/`

### 4. **Debug Systematically**
- Start with quick tests: `make test-quick`
- Run specific test suite: `make test-contactbar`
- Use verbose output: `swift test --verbose`
- Check test reports: `test_results/`

## 🎉 Success Metrics

Your testing workflow is working well when:
- ✅ All 109 tests pass consistently
- ✅ Pre-commit hooks prevent broken commits
- ✅ CI/CD pipeline runs successfully
- ✅ Performance tests show consistent results
- ✅ Test coverage remains high (>90%)

## 📞 Getting Help

If you encounter issues:
1. Check the test log files in `test_results/`
2. Run tests with verbose output: `swift test --verbose`
3. Review the test reports for specific failure details
4. Use the Makefile commands for easy testing

---

**Happy Testing! 🧪✨**
