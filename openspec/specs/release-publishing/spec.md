# release-publishing Specification

## Purpose
How the app and the packages GPSLoggerKit and GPSLoggerKitGPL are published: versions, Git tags, GitHub releases and the use of the packages in the app by version.

## Requirements

### Requirement: Own repositories of the packages
GPSLoggerKit and GPSLoggerKitGPL MUST each live in their own public GitHub repository, with `Package.swift` at the root, their license file and their provenance list. The repository of GPSLoggerKit MUST NOT contain code from GPL or CC-BY-SA licensed source code, not even in its Git history.

#### Scenario: Use the package by URL
- **WHEN** another Swift project declares GPSLoggerKit by repository URL with a published version as a dependency
- **THEN** the Swift Package Manager loads the package and the project builds, without other parts of the gpsloader repository

#### Scenario: History of the MIT package
- **WHEN** the Git history of the GPSLoggerKit repository is examined
- **THEN** it contains only files of the package and no files of GPSLoggerKitGPL, the app or gpsbabel

### Requirement: Versions
The app and the packages SHALL use versions according to Semantic Versioning, starting with 0.1.0. Every published version MUST have a Git tag with exactly the version number, for example `0.1.0`. A published tag MUST NOT be moved afterwards.

#### Scenario: First versions
- **WHEN** the app and the packages are published for the first time
- **THEN** they have the version 0.1.0, and the tag `0.1.0` points to the published commit in each repository

#### Scenario: Version of the app
- **WHEN** the Info.plist of the published app is read
- **THEN** `CFBundleShortVersionString` matches the tag of the release

### Requirement: Packages in the app by version
The app MUST use GPSLoggerKit and GPSLoggerKitGPL through their repository URLs and published versions. The resolved versions MUST be recorded in the app repository, so that every release build uses the same package versions. While the packages are below 1.0.0, the app SHALL only allow versions of the same minor version, for example 0.1.x.

#### Scenario: Reproducible release build
- **WHEN** a release build of the app is created from a clean checkout
- **THEN** it uses exactly the package versions recorded in the app repository

#### Scenario: New minor version of a package
- **WHEN** a package publishes the version 0.2.0
- **THEN** the app takes it over only after an explicit change of its dependency

### Requirement: GitHub release of the app
A release of the app MUST appear on GitHub in the app repository. It MUST contain the tag of the version, release notes, the notarized ZIP and its SHA-256 checksum. The release script SHALL create it only when explicitly asked to. Before that it MUST check that the commit is clean and pushed and that the notarization succeeded. Versions below 1.0.0 MUST appear as a pre-release.

#### Scenario: Create a release
- **WHEN** the developer runs the release script with the option to publish and all checks pass
- **THEN** there is a release on GitHub for the tag of the version with the release notes, the ZIP and the checksum
- **AND** for a version below 1.0.0 it is marked as a pre-release

#### Scenario: No release without the option
- **WHEN** the release script runs without the option to publish
- **THEN** the ZIP and the checksum are created locally, but neither a tag nor a release on GitHub

#### Scenario: Notarization rejected
- **WHEN** Apple rejects the notarization
- **THEN** the script stops before a tag or a release is created on GitHub

#### Scenario: Version already published
- **WHEN** a tag or a release exists for the version already
- **THEN** the script stops before the build and does not change the existing release

#### Scenario: Release notes missing
- **WHEN** there are no release notes for the version
- **THEN** the script stops before the build

### Requirement: GitHub release of the packages
A release of a package MUST appear on GitHub in the package repository, with the tag of the version and release notes. Before that the package's release script MUST check that the commit is clean and pushed and that the tests pass. For GPSLoggerKit this includes the tests on macOS and on an iOS simulator. Versions below 1.0.0 MUST appear as a pre-release.

#### Scenario: Publish a package
- **WHEN** the developer runs the release script of a package and all checks pass
- **THEN** the package repository has a tag and a GitHub release for the version with the release notes

#### Scenario: Tests fail
- **WHEN** a test of the package fails
- **THEN** neither a tag nor a release is created

### Requirement: Source code of every app version
For every release of the app the complete source code MUST be public: the commit of the tag in the app repository and the tags of the included package versions in their repositories. The About window SHALL link the app repository and the GPSLoggerKit repository.

#### Scenario: Source code for a release
- **WHEN** a user looks for the source code of a published version of the app
- **THEN** they find the tag of this version in the app repository, and its `Package.resolved` names the tags of the packages, which are in their public repositories
