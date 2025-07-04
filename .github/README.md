# GitHub Actions CI/CD for DownloadKit

This directory contains GitHub Actions workflows for continuous integration and testing of the DownloadKit library.

## Workflows

### 1. `tests.yml` - Comprehensive Test Suite
**Triggers**: Push to `main`/`master` branches

A comprehensive test suite that runs when code is merged to the main branch. This workflow ensures the library maintains high quality and compatibility across platforms.

#### Jobs:
- **macOS Tests**: Tests on macOS with Swift 5.9, 5.10, and 6.0
- **iOS Simulator Tests**: Tests on iPhone 14 (iOS 16) and iPhone 15 (iOS 17)  
- **Swift Compatibility**: Validates Swift Package Manager compatibility
- **Code Quality**: Linting, formatting, and build warning checks
- **Priority System Tests**: Dedicated tests for the download priority system
- **Realm Compatibility**: Tests for Realm database integration
- **Performance Tests**: Performance-critical functionality validation

#### Features:
- ✅ Code coverage reporting (Codecov integration)
- ✅ Multi-platform testing (macOS, iOS)
- ✅ Multiple Swift version compatibility
- ✅ Comprehensive test categorization
- ✅ Detailed test results summary

### 2. `pr-checks.yml` - Fast Pull Request Validation
**Triggers**: Pull requests to `main`/`master` branches

A fast, focused workflow optimized for pull request validation. Provides quick feedback to developers while ensuring essential functionality works.

#### Jobs:
- **Quick Validation**: Fast package validation and core tests
- **Essential Tests**: Priority, storage, memory, cache, and integration tests
- **Build Verification**: Debug and release build validation
- **iOS Compatibility**: Basic iOS build and test verification

#### Features:
- ⚡ Optimized for speed (parallel execution)
- ✅ Automatic cancellation of outdated runs
- ✅ Clear pass/fail status for merge decisions
- ✅ Comprehensive PR summary with next steps

## Test Categories

### Core Functionality
- **ResourceManagerTests**: Core download manager functionality
- **DownloadPriorityTests**: Priority system (normal, high, urgent)
- **StorageDownloadTests**: Storage priority and file management

### Data Layer
- **MemoryCacheTests**: In-memory caching functionality
- **LocalCacheManagerTests**: Local file cache management
- **RealmCacheTests**: Realm database integration

### Performance & Integration
- **AsyncPriorityQueueTests**: Async queue performance
- **ResourceManagerIntegrationTests**: End-to-end integration tests
- **WebDownloadProcessorTests**: Network download processing

## Setup Requirements

### Required GitHub Secrets
For full functionality, configure these secrets in your repository:

```bash
CODECOV_TOKEN  # For code coverage reporting (optional)
```

### Xcode and iOS Simulator Support
The workflows automatically:
- Install latest stable Xcode
- Set up iOS simulators for iPhone 14 and iPhone 15
- Test on iOS 16.0 and 17.0

### Swift Version Support
Tests run on multiple Swift versions:
- Swift 5.9 (minimum supported)
- Swift 5.10 (current stable)
- Swift 6.0 (latest with strict concurrency)

## Usage

### For Pull Requests
1. Create a pull request to `main` or `master`
2. The `pr-checks.yml` workflow runs automatically
3. Review the check results in the PR
4. Fix any failing checks before requesting review

### For Main Branch
1. Merge approved pull requests to `main`
2. The comprehensive `tests.yml` workflow runs
3. Monitor test results and code coverage
4. Address any failures promptly

## Workflow Optimization

### Caching Strategy
- Swift Package Manager dependencies are cached
- Separate cache keys for different platforms and configurations
- Cache restoration improves workflow speed

### Parallel Execution
- PR checks run essential tests in parallel
- Build verification runs debug and release builds simultaneously
- iOS compatibility tests run independently

### Resource Usage
- Uses `macos-latest` runners for Swift/iOS support
- Optimized build commands to minimize resource usage
- Strategic use of build caching

## Troubleshooting

### Common Issues

**Build Failures**
- Check Swift version compatibility
- Verify Package.swift dependencies
- Review build warnings and errors

**Test Failures**
- Check test logs in GitHub Actions
- Run tests locally: `swift test`
- Verify Realm database compatibility

**iOS Build Issues**
- Ensure iOS deployment target compatibility
- Check Xcode version requirements
- Verify simulator availability

### Local Testing
To run the same tests locally:

```bash
# Run all tests
swift test

# Run specific test categories
swift test --filter DownloadPriorityTests
swift test --filter StorageDownloadTests
swift test --filter MemoryCacheTests

# Build for iOS (requires Xcode)
xcodebuild build-for-testing \
  -scheme DownloadKit \
  -destination "platform=iOS Simulator,name=iPhone 15,OS=17.0"
```

## Monitoring and Maintenance

### Workflow Updates
- Keep GitHub Actions up to date with `@v4` or latest
- Update Swift versions as new releases become available
- Adjust iOS simulator versions for latest iOS releases

### Performance Monitoring
- Monitor workflow execution times
- Optimize slow test suites
- Review and update caching strategies

### Dependency Management
- Keep Swift Package Manager dependencies updated
- Monitor for security vulnerabilities
- Test with latest Realm Swift versions

## Contributing

When adding new tests or features:

1. **Add appropriate test coverage** for new functionality
2. **Update workflow filters** if adding new test files
3. **Test locally** before submitting pull requests
4. **Consider performance impact** on CI/CD execution time

For questions or issues with the CI/CD setup, please open an issue in the repository.
