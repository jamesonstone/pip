.DEFAULT_GOAL := help

.PHONY: help generate test build-ios build-macos

help:
	@printf '%s\n' 'Project developer workflow'
	@printf '%s\n' ''
	@printf '%s\n' '  generate     write Pip.xcodeproj from project.yml'
	@printf '%s\n' '  test         run PipCore unit tests'
	@printf '%s\n' '  build-ios    unsigned iOS Simulator build'
	@printf '%s\n' '  build-macos  unsigned macOS build'
	@printf '%s\n' ''
	@printf '%s\n' 'Requires macOS, Xcode, and XcodeGen.'
	@printf '%s\n' 'Copy Config/Signing.xcconfig.example to Config/Signing.xcconfig first.'

generate:
	xcodegen generate

test:
	swift test --package-path Packages/PipCore

build-ios:
	xcodebuild -project Pip.xcodeproj -scheme Pip-iOS -destination 'generic/platform=iOS Simulator' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE= build

build-macos:
	xcodebuild -project Pip.xcodeproj -scheme Pip-macOS -destination 'generic/platform=macOS' -configuration Debug CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual DEVELOPMENT_TEAM= PROVISIONING_PROFILE= build
