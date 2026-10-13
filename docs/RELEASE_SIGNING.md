# Release Signing for EDITORS-PRO

This document describes how to sign release builds of EDITORS-PRO for
Play Store distribution. There are two flows: local signing (for
testing) and CI signing (for production releases).

## 1. Generate a release keystore

```bash
keytool -genkey -v \
  -keystore editors-pro-upload.jks \
  -keyalg RSA -keysize 2048 -validity 10000 \
  -alias upload
```

You'll be prompted for:
- A keystore password (pick a strong one; store in your password manager)
- A key password (can be the same as the keystore password)
- Your name, organization, etc.

**Keep this file safe.** If you lose it, you cannot publish updates to
the same Play Store listing. Back it up to multiple locations (encrypted
cloud storage, USB drive, etc.).

**Never commit the .jks file to git.** The `.gitignore` already
excludes `*.jks`, `*.keystore`, and `key.properties`.

## 2. Configure local signing

Create a file at `android/key.properties` with the keystore details:

```properties
storeFile=/absolute/path/to/editors-pro-upload.jks
storePassword=your-keystore-password
keyAlias=upload
keyPassword=your-key-password
```

The `android/app/build.gradle.kts` signing config reads this file
automatically when present. To verify, run:

```bash
flutter build appbundle --release
```

The output AAB will be signed with your release key. You can verify
with:

```bash
jarsigner -verify -verbose -certs build/app/outputs/bundle/release/app-release.aab
```

## 3. Configure CI signing (GitHub Actions)

For CI builds to produce signed release artifacts, add the following
secrets to your GitHub repository (Settings → Secrets and variables →
Actions):

| Secret name | Value |
|---|---|
| `EDITORS_PRO_STORE_FILE` | Absolute path where the keystore will be placed on the runner (e.g. `/tmp/editors-pro-upload.jks`) |
| `EDITORS_PRO_STORE_PASSWORD` | The keystore password |
| `EDITORS_PRO_KEY_ALIAS` | The key alias (e.g. `upload`) |
| `EDITORS_PRO_KEY_PASSWORD` | The key password |
| `EDITORS_PRO_KEYSTORE_BASE64` | Base64-encoded contents of the .jks file (see below) |

To base64-encode the keystore:

```bash
base64 -w 0 editors-pro-upload.jks > keystore.b64
# Copy the contents of keystore.b64 into the EDITORS_PRO_KEYSTORE_BASE64 secret
```

The CI workflow reads the signing values and decodes the keystore before
building. Configure all five secrets together; partial configuration fails
the build. Without them, CI can still produce test APK/AAB artifacts using
the debug key, but a `v*` tag will not create a GitHub release.

## 4. Play Store upload

Once you have a signed AAB:

1. Go to the [Play Console](https://play.google.com/console).
2. Select your app → Production → Create new release.
3. Upload the AAB.
4. Fill in release notes.
5. Review and roll out.

The first time you upload, you'll also need to complete the
"App content" and "Data safety" sections in the Play Console.

## 5. App signing by Google Play (recommended)

For maximum security, enroll in **Play App Signing**. This lets Google
hold your signing key in their infrastructure and rotate it if needed.
You'll upload your upload key (the one generated above) and Google
will re-sign with the app signing key for distribution.

To enroll:
1. Play Console → Setup → App integrity → App signing.
2. Follow the prompts to upload your upload key.
3. From this point on, you sign with your upload key, Google re-signs
   with the app signing key.

If you lose your upload key, you can request a reset via Play Console
support — this is impossible without Play App Signing enrolled.

## 6. Rotating the keystore

If your keystore is compromised:

1. Generate a new keystore (step 1).
2. Update `key.properties` locally (step 2) and the GitHub secrets (step 3).
3. If enrolled in Play App Signing, request an upload key reset via
   Play Console support.
4. Publish a new release signed with the new key.

## 7. Verifying the signature

```bash
# Verify the APK signature
apksigner verify --verbose --print-certs \
  build/app/outputs/flutter-apk/app-release.apk

# Verify the AAB signature
jarsigner -verify -verbose -certs \
  build/app/outputs/bundle/release/app-release.aab
```

Both should print "jar verified." and the certificate fingerprint
should match your keystore.
