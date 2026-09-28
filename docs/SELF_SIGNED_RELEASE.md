# Releases with a consistent self-signed certificate

**English** | [简体中文](SELF_SIGNED_RELEASE.zh-CN.md)

When no Apple Developer ID is available, cpsmart uses a self-signed certificate kept by the release maintainer to preserve its code identity across versions. Only the maintainer creates this certificate. Users do not need to create, install, or trust it.

This certificate does not replace Developer ID, allow Apple notarization, or remove Gatekeeper's first-launch warning. Its purpose is to give different releases a stable designated requirement, so macOS can recognize an updated cpsmart as the same app that was previously granted permission.

## Create the release identity

Perform these steps once on the designated release Mac:

1. Open Keychain Access.
2. Choose Keychain Access → Certificate Assistant → Create a Certificate.
3. Enter `cpsmart Release Signing` as the name.
4. Set Identity Type to Self Signed Root.
5. Set Certificate Type to Code Signing.
6. Select Let me override defaults.
7. Use a unique serial number and preferably a 3650-day validity period; keep the other defaults.
8. Save the certificate in the current user's login keychain.
9. Expand the certificate under My Certificates and confirm that it has a private key.
10. Open the certificate's Trust section and set only Code Signing to Always Trust. Leave the other uses at their defaults.

Do not create another certificate with the same name. A matching name does not mean a matching identity; only the original certificate and private key can preserve it.

## Back up and share the certificate

Select `cpsmart Release Signing` under My Certificates in Keychain Access. Export it as a `.p12` containing the private key, protected with a separate strong password.

- Send the `.p12` and its password to release collaborators through two different secure channels.
- Never commit or publish the `.p12`, password, private key, or an unencrypted export in Git, a GitHub Release, a public cloud link, or a group chat.
- Keep at least one encrypted offline backup. If the private key is lost, creating a same-named certificate will not restore the identity.
- Anyone with the `.p12` can produce a package macOS may treat as official cpsmart. Control access as you would release permissions.

A collaborator can import it with:

```bash
bash Scripts/import_signing_identity.sh /secure/path/cpsmart-release-signing.p12
```

macOS asks for the password in a secure dialog, so it does not enter the shell history or repository. The script trusts the certificate only for code signing. The collaborator may also need to approve a keychain password or Touch ID prompt. After import, confirm that My Certificates in Keychain Access shows both the certificate and its private key.

## Build a self-signed package

```bash
bash Scripts/build_dmg.sh --self-signed \
  --sign-identity "cpsmart Release Signing"
```

This mode enables Hardened Runtime, explicitly disables Apple's timestamp service (which does not apply to this self-signed certificate), and rejects a version-specific designated requirement containing `cdhash`. It does not submit the package for notarization.

For local development and ordinary tests, continue to use:

```bash
bash Scripts/build_dmg.sh --local
```

Use the consistent release identity only for versions you intend to distribute.

## Validate the first migration and subsequent updates

Users moving from an ad hoc signed build to the consistent certificate should expect to grant Accessibility permission one final time. Do not proactively reset that permission on subsequent updates. Use the “clear old record” recovery option only when automatic pasting actually fails.

Before release, create at least two packages with different build numbers signed by the same certificate:

1. Install the first package, grant Accessibility permission in System Settings, and confirm automatic pasting works.
2. Quit cpsmart completely and replace `/Applications/cpsmart.app` with the second package.
3. Reopen it without clearing the permission. Confirm the switch is still present in System Settings and automatic pasting works.
4. Complete the installed-package interaction tests in the [multi-display and input testing checklist](MULTI_DISPLAY_TESTING.md) on both the primary and a secondary display.

If the second version loses permission, stop the release and compare the designated requirements of both packages. Do not hide an unstable identity by resetting permission after every update.

## Switching to Developer ID in the future

Developer ID and the current self-signed certificate are different identities. On the first switch, users may need to grant permission again. Afterward, keep using the same Developer ID identity and complete Apple notarization for each release.
