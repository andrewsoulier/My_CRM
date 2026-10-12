# My CRM Automated Testing Suite

This directory contains comprehensive automated tests for the My CRM application, covering unit tests, integration tests, and UI tests for all critical functionality.

## 🧪 Test Structure

### Test Organization
```
Tests/
├── TestFixtures/           # Reusable test data and mock objects
│   └── TestData.swift     # Test contacts, groups, and mock data provider
├── UnitTests/             # Fast, isolated tests for individual components
│   ├── GroupManagementTests.swift
│   └── DragDropTests.swift
├── IntegrationTests/      # Tests for component interactions and workflows
│   ├── UserWorkflowTests.swift
│   └── DatabaseIntegrationTests.swift
├── UITests/              # End-to-end UI interaction tests
│   └── DragDropUITests.swift
├── run_tests.sh          # Test runner script
└── README.md             # This file
```

## 🚀 Quick Start

### Running All Tests
```bash
# Run all tests
./Tests/run_tests.sh

# Run with verbose output
./Tests/run_tests.sh --verbose

# Clean build before testing
./Tests/run_tests.sh --clean
```

### Running Specific Test Suites
```bash
# Unit tests only
./Tests/run_tests.sh --unit-only

# Integration tests only
./Tests/run_tests.sh --integration-only

# UI tests only
./Tests/run_tests.sh --ui-only
```

### Running Individual Tests
```bash
# Run specific test class
xcodebuild test -scheme "My CRM" -destination 'platform=macOS' -only-testing:MyCRMTests/GroupManagementTests

# Run specific test method
xcodebuild test -scheme "My CRM" -destination 'platform=macOS' -only-testing:MyCRMTests/GroupManagementTests/testGroupCreation
```

## 📋 Test Coverage

### Unit Tests
**Group Management Tests** (`GroupManagementTests.swift`)
- ✅ Group creation with proper properties
- ✅ Group persistence to data provider
- ✅ Database ID assignment
- ✅ Deck creation (isDeck = true)
- ✅ Single and multiple contact addition
- ✅ Duplicate contact handling
- ✅ Contact removal from groups
- ✅ Group clearing
- ✅ Group deletion
- ✅ Parent-child relationships
- ✅ Group validation

**Drag and Drop Tests** (`DragDropTests.swift`)
- ✅ Contact drag item creation from various sources
- ✅ Drop target validation
- ✅ Contact drop from contacts bar to group
- ✅ Contact movement between groups
- ✅ Contact copying between groups
- ✅ Same-group drop handling
- ✅ Drag item validation
- ✅ Undo functionality
- ✅ Error handling

### Integration Tests
**User Workflow Tests** (`UserWorkflowTests.swift`)
- ✅ Complete group creation and contact addition workflow
- ✅ Drag and drop from contacts bar to group
- ✅ Move contacts between groups
- ✅ Copy contacts between groups
- ✅ Deck creation and organization
- ✅ Undo and redo operations
- ✅ Error recovery and data consistency

**Database Integration Tests** (`DatabaseIntegrationTests.swift`)
- ✅ Contact CRUD operations
- ✅ Group CRUD operations
- ✅ Deck CRUD operations
- ✅ Group/deck distinction
- ✅ Search operations (name, phone, email)
- ✅ Data consistency and referential integrity
- ✅ Concurrent operations
- ✅ Error handling

### UI Tests
**Drag and Drop UI Tests** (`DragDropUITests.swift`)
- ✅ Contact drag from contacts bar with preview
- ✅ Contact drop on canvas
- ✅ Group creation dialog
- ✅ Group drag and drop with indicators
- ✅ Keyboard shortcuts (G, Escape)
- ✅ Multi-select operations
- ✅ Context menus for contacts and groups

## 🎯 Test Data

### Test Contacts
The test suite uses 5 standardized test contacts:
- **Test1** (101-101-0001) - test1@example.com
- **Test2** (101-101-0002) - test2@example.com
- **Test3** (101-101-0003) - test3@example.com
- **Test4** (101-101-0004) - test4@example.com
- **Test5** (101-101-0005) - test5@example.com

### Test Groups
The test suite uses 5 standardized test groups:
- **TestGroup1** (Blue) - UUID: 11111111-1111-1111-1111-111111111111
- **TestGroup2** (Green) - UUID: 22222222-2222-2222-2222-222222222222
- **TestGroup3** (Red) - UUID: 33333333-3333-3333-3333-333333333333
- **TestGroup4** (Orange) - UUID: 44444444-4444-4444-4444-444444444444
- **TestGroup5** (Purple) - UUID: 55555555-5555-5555-5555-555555555555

### Test Decks
The test suite uses 2 standardized test decks:
- **TestDeck1** (Cyan) - UUID: AAAAAAAA-AAAA-AAAA-AAAA-AAAAAAAAAAAA
- **TestDeck2** (Mint) - UUID: BBBBBBBB-BBBB-BBBB-BBBB-BBBBBBBBBBBB

## 🔧 Test Framework

### Quick/Nimble
The test suite uses [Quick](https://github.com/Quick/Quick) and [Nimble](https://github.com/Quick/Nimble) for expressive, BDD-style testing:

```swift
describe("Group Creation") {
    context("when creating a new group") {
        it("should create a group with correct properties") {
            let group = TestData.createTestGroup(name: "New Test Group")
            
            expect(group.name).to(equal("New Test Group"))
            expect(group.isDeck).to(beFalse())
            expect(group.memberCount).to(equal(0))
        }
    }
}
```

### Mock Data Provider
Tests use a `MockDataProvider` that implements the `DataProvider` protocol without requiring a real database:

```swift
let dataProvider = TestData.createMockDataProvider()
dataProvider.contacts = TestData.testContacts
dataProvider.groups = TestData.testGroups
```

## 🎨 Test Scenarios

### Critical User Workflows Tested

1. **Group Creation Workflow**
   - User creates new group
   - User adds contacts to group
   - Group persists to database
   - Group appears in groups toolbar

2. **Drag and Drop Workflow**
   - User drags contacts from contacts bar
   - User drops contacts on group
   - Contacts are added to group
   - Undo operation is available

3. **Contact Movement Workflow**
   - User moves contacts between groups
   - Source group loses contacts
   - Target group gains contacts
   - Undo restores original state

4. **Contact Copying Workflow**
   - User copies contacts between groups
   - Source group retains contacts
   - Target group gains contacts
   - Both groups have correct member counts

5. **Error Recovery Workflow**
   - Invalid operations are handled gracefully
   - Data consistency is maintained
   - User receives appropriate feedback

## 🚨 Error Scenarios Tested

- Empty drag items
- Non-existent groups
- Duplicate contact creation
- Concurrent database operations
- Invalid drop targets
- Network/database failures

## 📊 Performance Considerations

### Test Execution Speed
- **Unit Tests**: ~100ms per test suite
- **Integration Tests**: ~500ms per test suite
- **UI Tests**: ~2-5s per test suite

### Memory Usage
- Tests use in-memory databases
- Mock data providers minimize memory footprint
- Proper cleanup in `afterEach` blocks

## 🔍 Debugging Tests

### Verbose Output
```bash
./Tests/run_tests.sh --verbose
```

### Individual Test Debugging
```bash
# Run with Xcode debugger
xcodebuild test -scheme "My CRM" -destination 'platform=macOS' -only-testing:MyCRMTests/GroupManagementTests
```

### Test Logs
Test logs are saved to:
- `build.log` - Build output
- `groupmanagementtests.log` - Group management test output
- `dragdroptests.log` - Drag and drop test output
- etc.

## 🛠️ Adding New Tests

### 1. Create Test File
```swift
import Quick
import Nimble
@testable import MyCRM

class NewFeatureTests: QuickSpec {
    override func spec() {
        describe("New Feature") {
            // Your tests here
        }
    }
}
```

### 2. Add Test Data
Update `TestData.swift` with new test fixtures if needed.

### 3. Update Test Runner
Add new test suite to `run_tests.sh` if needed.

### 4. Run Tests
```bash
./Tests/run_tests.sh --verbose
```

## 📈 Continuous Integration

### GitHub Actions (Recommended)
```yaml
name: Tests
on: [push, pull_request]
jobs:
  test:
    runs-on: macos-latest
    steps:
      - uses: actions/checkout@v2
      - name: Run Tests
        run: ./Tests/run_tests.sh --clean
```

### Local CI
```bash
# Add to your build script
./Tests/run_tests.sh --clean
if [ $? -ne 0 ]; then
    echo "Tests failed!"
    exit 1
fi
```

## 🎯 Best Practices

### Test Organization
- Group related tests in `describe` blocks
- Use `context` for different scenarios
- Use `it` for individual test cases
- Use `beforeEach` and `afterEach` for setup/cleanup

### Test Data
- Use `TestData` fixtures for consistent test data
- Create specific test data for edge cases
- Clean up test data after each test

### Assertions
- Use descriptive `expect` statements
- Test both positive and negative cases
- Verify error conditions and edge cases

### Performance
- Keep unit tests fast (< 100ms)
- Use mock objects for external dependencies
- Avoid UI tests for business logic

## 🐛 Troubleshooting

### Common Issues

**Tests fail to compile**
- Check that Quick/Nimble are properly imported
- Verify test target includes all necessary files
- Run `xcodebuild clean` and rebuild

**Tests pass locally but fail in CI**
- Check environment variables
- Verify test database paths
- Check for timing issues in async tests

**UI tests fail**
- Ensure app is properly launched
- Check accessibility identifiers
- Verify UI elements exist before interaction

### Getting Help
1. Check test logs for detailed error messages
2. Run tests with `--verbose` flag
3. Use Xcode debugger for complex issues
4. Review test documentation and examples

---

**Happy Testing! 🎉**

For questions or issues with the test suite, please refer to the main project documentation or create an issue in the project repository.
