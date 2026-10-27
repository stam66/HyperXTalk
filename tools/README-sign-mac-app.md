# Signing any app the HyperXTalk way

`sign-mac-app.sh` code-signs an arbitrary macOS app bundle with the hardened
runtime and the JIT entitlements HyperXTalk / OpenXTalk engines need, signing
nested code inside-out and never using `codesign --deep` (see the comments in
the script for why). It is self-contained: the entitlements are embedded, so
it does not need this repository to run.

`Sign App.applescript` is a drag-and-drop front end for it.

## Install once

```bash
mkdir -p ~/bin
cp tools/sign-mac-app.sh ~/bin/
chmod +x ~/bin/sign-mac-app.sh
```

## Command line

```bash
~/bin/sign-mac-app.sh /Applications/OXT-beyond.app                 # ad-hoc
~/bin/sign-mac-app.sh /Applications/Foo.app -i "Developer ID Application: Name (TEAMID)"
~/bin/sign-mac-app.sh /Applications/Foo.app -e my.entitlements     # custom entitlements
~/bin/sign-mac-app.sh --help
```

## Droplet / mini-app

1. Open `tools/Sign App.applescript` in Script Editor.
2. File > Export…, File Format: **Application**, save as `Sign App.app`
   (for example in `~/Applications`).
3. Make sure the applet can find the shell script. Any one of these works:
   - the `~/bin` install above, or
   - keep `sign-mac-app.sh` in the same folder as `Sign App.app`, or
   - copy it into the applet: right-click `Sign App.app` > Show Package
     Contents > `Contents/Resources/`.
4. Drop an app onto `Sign App.app`, or double-click it and pick one.
   It asks whether to sign ad-hoc or with a Developer ID certificate from
   your keychain, then shows the result.

The first time the applet runs `codesign` with a Developer ID identity,
macOS may ask for keychain access; click **Always Allow**.

## Notes

- An ad-hoc signature satisfies the kernel and the JIT entitlement on your
  own Mac. Gatekeeper on other Macs still needs a Developer ID signature
  plus notarization.
- The script strips extended attributes (including quarantine) before
  signing, because `codesign` refuses bundles carrying Finder metadata.
