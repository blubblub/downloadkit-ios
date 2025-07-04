# GitHub Actions Status Badges

Add these badges to your main README.md file to show the current status of your CI/CD workflows.

## Comprehensive Test Suite
[![Tests](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/tests.yml/badge.svg)](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/tests.yml)

## Pull Request Checks
[![PR Checks](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/YOUR_USERNAME/YOUR_REPO/actions/workflows/pr-checks.yml)

## Usage in README.md

Replace `YOUR_USERNAME` and `YOUR_REPO` with your actual GitHub username and repository name:

```markdown
# DownloadKit

[![Tests](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/tests.yml/badge.svg)](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/tests.yml)
[![PR Checks](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/pr-checks.yml)

A powerful, concurrent download manager for iOS and macOS applications.
```

## Additional Badges

You can also add these optional badges:

### Swift Version
![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)
![Swift 5.9+](https://img.shields.io/badge/Swift-5.9+-orange.svg)

### Platform Support  
![iOS 15.0+](https://img.shields.io/badge/iOS-15.0+-blue.svg)
![macOS 12.0+](https://img.shields.io/badge/macOS-12.0+-blue.svg)

### Code Coverage (if using Codecov)
[![codecov](https://codecov.io/gh/YOUR_USERNAME/YOUR_REPO/branch/main/graph/badge.svg)](https://codecov.io/gh/YOUR_USERNAME/YOUR_REPO)

### Swift Package Manager
![SPM Compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)

## Complete Example

```markdown
# DownloadKit

[![Tests](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/tests.yml/badge.svg)](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/tests.yml)
[![PR Checks](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/pr-checks.yml/badge.svg)](https://github.com/YOUR_USERNAME/downloadkit-ios/actions/workflows/pr-checks.yml)
[![codecov](https://codecov.io/gh/YOUR_USERNAME/downloadkit-ios/branch/main/graph/badge.svg)](https://codecov.io/gh/YOUR_USERNAME/downloadkit-ios)

![Swift 6.0](https://img.shields.io/badge/Swift-6.0-orange.svg)
![iOS 15.0+](https://img.shields.io/badge/iOS-15.0+-blue.svg)
![macOS 12.0+](https://img.shields.io/badge/macOS-12.0+-blue.svg)
![SPM Compatible](https://img.shields.io/badge/SPM-compatible-brightgreen.svg)

A powerful, concurrent download manager for iOS and macOS applications with advanced priority management and Realm database integration.
```
