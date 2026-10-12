#!/bin/bash

# My CRM Test Runner Script
# This script runs all tests and provides detailed reporting

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
PROJECT_NAME="My CRM"
TEST_RESULTS_DIR="test_results"
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
LOG_FILE="${TEST_RESULTS_DIR}/test_run_${TIMESTAMP}.log"

# Create test results directory
mkdir -p "$TEST_RESULTS_DIR"

echo -e "${BLUE}🧪 Starting ${PROJECT_NAME} Test Suite${NC}"
echo -e "${BLUE}================================${NC}"
echo "Timestamp: $(date)"
echo "Log file: $LOG_FILE"
echo ""

# Function to run tests with detailed output
run_tests() {
    local test_filter="$1"
    local test_name="$2"
    
    echo -e "${YELLOW}Running $test_name...${NC}"
    
    if [ -n "$test_filter" ]; then
        swift test --filter "$test_filter" 2>&1 | tee -a "$LOG_FILE"
    else
        swift test 2>&1 | tee -a "$LOG_FILE"
    fi
    
    local exit_code=${PIPESTATUS[0]}
    
    if [ $exit_code -eq 0 ]; then
        echo -e "${GREEN}✅ $test_name PASSED${NC}"
    else
        echo -e "${RED}❌ $test_name FAILED${NC}"
    fi
    
    echo ""
    return $exit_code
}

# Function to generate test report
generate_report() {
    local report_file="${TEST_RESULTS_DIR}/test_report_${TIMESTAMP}.md"
    
    echo "# Test Report - $(date)" > "$report_file"
    echo "" >> "$report_file"
    echo "## Test Results" >> "$report_file"
    echo "" >> "$report_file"
    
    # Extract test results from log
    if grep -q "Test Suite.*passed" "$LOG_FILE"; then
        echo "✅ All tests passed" >> "$report_file"
    else
        echo "❌ Some tests failed" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "## Test Coverage" >> "$report_file"
    echo "" >> "$report_file"
    
    # Count test suites
    local test_suites=$(grep -c "Test Suite.*started" "$LOG_FILE" || echo "0")
    echo "- Test Suites: $test_suites" >> "$report_file"
    
    # Count individual tests
    local total_tests=$(grep -c "Test Case.*started" "$LOG_FILE" || echo "0")
    echo "- Total Tests: $total_tests" >> "$report_file"
    
    # Count passed tests
    local passed_tests=$(grep -c "Test Case.*passed" "$LOG_FILE" || echo "0")
    echo "- Passed Tests: $passed_tests" >> "$report_file"
    
    # Count failed tests
    local failed_tests=$(grep -c "Test Case.*failed" "$LOG_FILE" || echo "0")
    echo "- Failed Tests: $failed_tests" >> "$report_file"
    
    echo "" >> "$report_file"
    echo "## Performance" >> "$report_file"
    echo "" >> "$report_file"
    
    # Extract performance data
    if grep -q "Created.*groups in" "$LOG_FILE"; then
        local group_creation_time=$(grep "Created.*groups in" "$LOG_FILE" | tail -1 | sed 's/.*Created \([0-9]*\) groups in \([0-9.]*\) seconds.*/- Group Creation: \1 groups in \2 seconds/')
        echo "$group_creation_time" >> "$report_file"
    fi
    
    if grep -q "Added.*members in" "$LOG_FILE"; then
        local member_addition_time=$(grep "Added.*members in" "$LOG_FILE" | tail -1 | sed 's/.*Added \([0-9]*\) members in \([0-9.]*\) seconds.*/- Member Addition: \1 members in \2 seconds/')
        echo "$member_addition_time" >> "$report_file"
    fi
    
    echo "" >> "$report_file"
    echo "## Log File" >> "$report_file"
    echo "" >> "$report_file"
    echo "Full test log: \`$LOG_FILE\`" >> "$report_file"
    
    echo -e "${BLUE}📊 Test report generated: $report_file${NC}"
}

# Main test execution
main() {
    local overall_exit_code=0
    
    # Run all tests
    if ! run_tests "" "All Tests"; then
        overall_exit_code=1
    fi
    
    # Generate report
    generate_report
    
    # Summary
    echo -e "${BLUE}📋 Test Summary${NC}"
    echo -e "${BLUE}===============${NC}"
    
    if [ $overall_exit_code -eq 0 ]; then
        echo -e "${GREEN}🎉 All tests passed successfully!${NC}"
    else
        echo -e "${RED}💥 Some tests failed. Check the log for details.${NC}"
    fi
    
    echo ""
    echo -e "${BLUE}📁 Test artifacts:${NC}"
    echo "- Log file: $LOG_FILE"
    echo "- Report: ${TEST_RESULTS_DIR}/test_report_${TIMESTAMP}.md"
    echo "- Results directory: $TEST_RESULTS_DIR"
    
    exit $overall_exit_code
}

# Handle command line arguments
case "${1:-}" in
    "all")
        main
        ;;
    "group")
        run_tests "GroupManagementTests" "Group Management Tests"
        ;;
    "dragdrop")
        run_tests "DragDropGroupTests" "Drag & Drop Tests"
        ;;
    "operations")
        run_tests "GroupOperationsTests" "Group Operations Tests"
        ;;
    "database")
        run_tests "GroupDatabaseTests" "Database Tests"
        ;;
    "contactbar")
        run_tests "ContactBarToGroupsBarDragDropTests" "Contact Bar to Groups Bar Tests"
        ;;
    "basic")
        run_tests "SimpleXCTests" "Basic Model Tests"
        ;;
    "help"|"-h"|"--help")
        echo "Usage: $0 [command]"
        echo ""
        echo "Commands:"
        echo "  all        Run all tests (default)"
        echo "  group      Run group management tests"
        echo "  dragdrop   Run drag & drop tests"
        echo "  operations Run group operations tests"
        echo "  database   Run database tests"
        echo "  contactbar Run contact bar to groups bar tests"
        echo "  basic      Run basic model tests"
        echo "  help       Show this help message"
        ;;
    *)
        main
        ;;
esac