# Android and iOS Export

Platform toolchains, store requirements, and Godot export options change over time. Use documentation for the exact installed Godot 4.x release and the current target store. Never infer required SDK, JDK, Xcode, target API, or signing versions from an unrelated project.

## Shared Export Gate

Before platform-specific work:

- Confirm the editor version and install matching export templates.
- Confirm the main scene and release feature flags.
- Validate app name, version, icons, orientation, renderer, architectures, locale resources, and privacy-sensitive features.
- Audit export include/exclude filters so required runtime files are packaged and development-only files are not.
- Keep secrets and generated credentials outside version control.
- Build from a clean checkout or reproducible workspace when validating release packaging.
- Test the exported artifact, not a different editor-run build.

## Android

### Toolchain

Follow the matching Godot Android export guide to install its supported JDK and Android SDK components. Configure editor paths and verify device tooling can see a physical test device.

Do not globally replace a working toolchain merely because another Godot release recommends a newer component.

### Preset Review

- Unique reverse-domain package identifier.
- Version code that increases for every store release.
- User-visible version name.
- Supported CPU architectures and minimum/target SDK policy.
- Rendering method and any renderer fallback required by target devices.
- Orientation and resize behavior.
- Main, adaptive foreground/background, and monochrome icons where required.
- Only the permissions the shipped features actually use.
- Release build mode, resource filters, and package format.

Use an APK for direct device testing where appropriate. Produce the store-required Android App Bundle for a Play release. Confirm current store policy rather than assuming historical requirements.

### Signing

- Generate and retain the release keystore through the team's secure process.
- Keep keystore path, alias, and passwords out of tracked files and logs.
- Back up the signing identity according to the store's app-signing model.
- Do not install a release signed with a new key over an existing package signed with another key and misdiagnose the failure as an export bug.
- Verify the final artifact is release-signed and not exported with debug enabled.

### Device Checks

- Fresh install, upgrade over the previous release, and uninstall/reinstall.
- Launch from icon, deep link/notification if supported, and return from background.
- Back gesture/button behavior.
- Runtime permission denial, later grant, and permanent denial where applicable.
- Offline launch and network loss.
- Store-delivered asset/resource behavior if used.

## iOS

### Host and Toolchain

iOS export requires macOS, Xcode, matching Godot templates, and Apple signing access. Confirm the current Godot guide's simulator and renderer limitations; a simulator is not a substitute for a physical device.

### Preset and Xcode Review

- Unique reverse-domain bundle identifier.
- App Store team ID and intended signing team.
- Short version and build number progression.
- Device families, architectures, minimum OS, and orientation.
- App icons, launch presentation, display name, and supported locales.
- Required capabilities such as networking, Game Center, push, or in-app purchase.
- Usage-description strings for every privacy-sensitive API the app can invoke.
- Renderer and device support consistent with the project.

Export into a dedicated output directory, open the generated Xcode project, resolve signing/capability errors, and build to a physical device. Do not hand-edit generated output without documenting how that change is reproduced on the next export.

### Device and Distribution Checks

- Development build on at least one supported physical device.
- Archive with the intended release scheme.
- Validation/upload through the current Apple workflow.
- TestFlight build when distribution requires it.
- Fresh install and upgrade from the previous version.
- Background/foreground, lock, audio interruption, rotation, and permission denial.
- Store metadata and privacy declarations matching actual behavior.

## Command-Line Automation

After presets work interactively, automate with the same editor version and host requirements. A generic shape is:

```text
<godot> --headless --path <project-root> --export-release "<preset-name>" <output-path>
```

The preset name must exactly match `export_presets.cfg`. Output extension and host depend on the platform and preset. Inject credentials through the supported secret mechanism; never place them directly in a command committed to the repository.

CI should record:

- Godot version and template version.
- Host OS and platform toolchain versions.
- Preset and commit being built.
- Artifact checksum and build logs.
- Whether signing, notarization/store validation, and device tests ran.

## Release Checklist

- No export errors or unexpected warnings.
- Package/bundle identity matches the existing store listing.
- Version fields increased correctly.
- Release signing identity is correct and securely supplied.
- Debug features, remote debugging, and test endpoints are disabled as intended.
- Permissions and privacy text match real code paths.
- Correct renderer, architectures, orientation, and minimum OS/API.
- Icons and launch visuals render correctly on each device family.
- Save data migrates from the previous release.
- Analytics, crash reporting, purchases, links, notifications, and network security are tested if present.
- Final store artifact passes platform validation and a smoke test.

## Export Failure Triage

1. Capture the first actionable exporter/toolchain error, not only the final failure summary.
2. Confirm editor and template versions match.
3. Confirm the preset and output path are valid.
4. Confirm toolchain paths and supported versions from the matching docs.
5. Separate compilation, packaging, signing, installation, and runtime failures.
6. Reproduce with an unsigned/debug device build when that isolates signing, but return to the release artifact for final verification.
7. Remove secrets before sharing logs.
