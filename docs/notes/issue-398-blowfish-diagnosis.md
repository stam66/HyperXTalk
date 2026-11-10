# Issue 398: `encrypt ... using "blowfish"` fails in the shipped macOS build

Diagnosis of emily-elizabeth/HyperXTalk#398 (and the forum thread
hyperxtalk.discourse.group/t/.../155): on macOS the downloaded 0.9.15 app fails
on `encrypt "hello" using "blowfish" with password "world"`. Peter2 sees an SSL
"could not load the shared library" error; Brian Milby sees an empty result but
`aes-256-cbc` works; a build from main works for both of them.

## Root cause

Since April 2026 (f2e184e5b / ce9b0553c) the macOS engine links OpenSSL 3
statically from `prebuilt/lib/mac/libcustomcrypto.a`. That archive is not the
output of `prebuilt/scripts/build-openssl.sh`; `prebuilt/scripts/build-mac-extras.sh`
(run by `make prebuilt-mac`, locally and in CI) copies Homebrew's
`/opt/homebrew/opt/openssl@3/lib/libcrypto.a` over it. The two files are
byte-identical (md5 `03e34795f8849ac2c3a3d1d185037c07`, OpenSSL 3.6.2).

Homebrew builds OpenSSL 3 with the providers as loadable modules. The
`legacy` provider, which is what implements Blowfish, RC4, DES, CAST5, IDEA,
MD4 and RIPEMD160 in OpenSSL 3, is therefore not inside libcrypto.a at all. It
is a separate `legacy.dylib` under
`/opt/homebrew/Cellar/openssl@3/3.6.2/lib/ossl-modules`, and that absolute
path is compiled into libcrypto as `MODULESDIR`. Every shipped engine carries
it:

| Binary                                           | `ossl_legacy_provider_init` | Baked-in MODULESDIR                                      |
|--------------------------------------------------|-----------------------------|----------------------------------------------------------|
| 0.9.13 release DMG (14 May 2026)                 | absent                      | `/opt/homebrew/Cellar/openssl@3/3.6.2/lib/ossl-modules` |
| /Applications 0.9.16 (hand-assembled from main)  | absent                      | same                                                     |
| dev build from main, 10 Nov 2026                 | absent                      | same                                                     |

So `InitSSLCrypt()` in `engine/src/mcssl.cpp` calls
`OSSL_PROVIDER_load(NULL, "legacy")`, and libcrypto tries to `dlopen` that
Homebrew path at run time:

- On a Mac that has Homebrew `openssl@3` **3.6.2** installed (every developer
  who has run `make prebuilt-mac`, which is why "a build from main works"),
  the module loads and Blowfish works.
- On any other Mac (no Homebrew, or a different openssl@3 version so the
  Cellar path differs) the load fails. The return value was not checked, so
  the failure only left a DSO error on the OpenSSL error queue.

`EVP_get_cipherbyname("bf-cbc")` still succeeds, because the name table is
populated regardless of providers, so `the cipherNames` lists `bf`, `bf-cbc`,
`blowfish` and friends. `EVP_CipherInit` then fails because no loaded provider
implements the cipher, and `SSL_encode` returns NULL without setting `outlen`.
The wrapper reports whatever `ERR_get_error()` returns:

- if the stale DSO error is still queued, `the result` is
  ` (SSL error: could not load the shared library)` (Peter2's report);
- if something has drained the queue since startup, `the result` is empty and
  `it` is unchanged (Brian's "silent" failure); in that case the code also
  reached `ctxt.LegacyThrow(t_error)` with `t_error` uninitialised.

AES is unaffected because it lives in the default provider, which is compiled
into libcrypto.

Note that this does not depend on macOS Tahoe or on arm64; it depends only on
whether Homebrew openssl@3 3.6.2 happens to be installed on the user's Mac. It
also means the release will break for developers as soon as Homebrew bumps
openssl@3 past 3.6.2, because the Cellar path moves.

### Reproduction (headless, any of the three engines above)

`OPENSSL_MODULES` overrides the compiled-in module directory, so pointing it
at a non-existent folder reproduces a Mac without Homebrew openssl@3:

```
OPENSSL_MODULES=/nonexistent <engine> -ui bftest.livecodescript
```

With the startup handler encrypting "hello" with Blowfish then AES and putting
`the result` and `it`:

```
normal:                 blowfish: result=[] it=[U2FsdGVkX1+...]   aes: ok
OPENSSL_MODULES unset:  blowfish: result=[ (SSL error: could not load the shared library)] it=[]   aes: ok
```

`prebuilt/scripts/build-openssl.sh` already configures OpenSSL 3.x with
`no-module` (commit 6035b6d3d, exactly to avoid this), but on macOS it was
never used: its mac arm64 target name `darwin-arm64-cc` does not exist in
OpenSSL (only `darwin64-arm64-cc` does), and `build-mac-extras.sh` overwrote
the archives with Homebrew's anyway.

## Fix (this branch)

1. `prebuilt/scripts/build-mac-extras.sh`: stop copying Homebrew's archives.
   Build OpenSSL from source through `build-openssl.sh` (which passes
   `no-module`, so the default and legacy providers are compiled into
   libcrypto.a; the build log shows `-DSTATIC_LEGACY`) and install the result
   as `libcustomcrypto.a` / `libcustomssl.a`. The script now refuses to
   continue if the archive has no `ossl_legacy_provider_init`.
2. `prebuilt/scripts/build-openssl.sh`: use `darwin64-arm64-cc` for arm64.
3. `Makefile.Mac`: `openssl@3` is no longer a prerequisite of `prebuilt-mac`.
4. `engine/src/mcssl.cpp`: check the result of loading the legacy provider,
   clear the stale DSO error so it is not reported by unrelated SSL calls, and
   when `EVP_CipherInit` fails report
   `cipher not available: the OpenSSL legacy provider could not be loaded` in
   `the result` instead of an empty result or an uninitialised error code.

The release pipeline (`.github/workflows/build.yml` runs `make prebuilt-mac`
on the macOS runner) picks up the new archives automatically; the CI
`brew install openssl@3` line is still needed by libpq and is harmless.

## Verification (10 Nov 2026, arm64, Xcode 27.2)

OpenSSL 3.6.2 built through the patched `build-mac-extras.sh` path
(`build-openssl.sh`, target `livecode_darwin64-arm64-cc`, `no-module no-threads
shared -DOPENSSL_NO_ASYNC=1`; the compile lines carry `-DSTATIC_LEGACY`).
`nm libcustomcrypto.a` now lists `ossl_legacy_provider_init`; `strings` finds
no `/opt/homebrew` path. The `development` target relinked against it:

| Check                                       | Engine from main (Homebrew archive) | This branch, Homebrew archive | This branch, no-module archive |
|---------------------------------------------|-------------------------------------|-------------------------------|--------------------------------|
| `ossl_legacy_provider_init` in engine       | no                                  | no                            | yes                            |
| `/opt/homebrew` strings in engine           | yes                                 | yes                           | none                           |
| blowfish, Homebrew module reachable         | ok                                  | ok                            | ok                             |
| blowfish, `OPENSSL_MODULES=/nonexistent`    | fails (A)                           | fails (B)                     | ok                             |
| aes-256-cbc, either way                     | ok                                  | ok                            | ok                             |

- (A): `it` is empty and `the result` is ` (SSL error: could not load the shared library)`.
- (B): `it` is empty and `the result` is `cipher not available: the OpenSSL legacy provider could not be loaded (SSL error: unsupported)`.

Encrypt/decrypt round trips with `OPENSSL_MODULES=/nonexistent` on the fixed
engine: blowfish, bf-cbc, rc4, des-ede3-cbc, cast5-cbc and aes-256-cbc all
return the plaintext with an empty result.

Not verified here: a release built by CI with the new `prebuilt-mac` step, and
Windows/Linux (unchanged: Windows uses the prebuilt `openssl3` archive from
`prebuilt/unpacked`, Linux already builds through `build-openssl.sh`).

## Draft reply for GitHub issue 398

> I can reproduce this on the shipped macOS builds (checked the 0.9.13 DMG and
> engines built from current main), and it is not Tahoe-specific. Here is
> what is going on.
>
> Since the April switch to a statically linked OpenSSL 3 on macOS, the
> archive the engine links (`prebuilt/lib/mac/libcustomcrypto.a`) is a
> straight copy of Homebrew's `openssl@3` libcrypto.a
> (`prebuilt/scripts/build-mac-extras.sh` does the copy; the two files are
> byte-identical). Homebrew builds OpenSSL 3 with the providers as loadable
> modules, so the "legacy" provider, which is where OpenSSL 3 keeps Blowfish,
> RC4, DES, CAST5, IDEA, MD4 and RIPEMD160, is not inside libcrypto.a at all:
> it is `/opt/homebrew/Cellar/openssl@3/3.6.2/lib/ossl-modules/legacy.dylib`,
> and that absolute path is compiled into libcrypto as the module directory.
> The shipped engine still contains that string.
>
> At startup `InitSSLCrypt()` calls `OSSL_PROVIDER_load(NULL, "legacy")`,
> which makes libcrypto `dlopen` that Homebrew path. On a Mac with Homebrew
> openssl@3 3.6.2 installed, which is every machine that has run
> `make prebuilt-mac`, it loads and Blowfish works. That is why "a build from
> main works": it is the developer's Homebrew install doing the work, not the
> build. On any other Mac the load fails. The return value was not checked,
> so the only trace is a DSO error left on the OpenSSL error queue.
> `EVP_get_cipherbyname("bf-cbc")` still succeeds (the name table does not
> depend on providers, so `the cipherNames` still lists Blowfish), but
> `EVP_CipherInit` then fails because nothing implements the cipher. Depending
> on whether that queued error is still there when `encrypt` runs, you get
> either `the result` = " (SSL error: could not load the shared library)"
> (Peter2) or an empty result and an empty `it` (Brian). AES is in the default
> provider, which is compiled in, so it is unaffected.
>
> You can reproduce it on a Mac that does have Homebrew openssl@3 by hiding
> the modules directory: `OPENSSL_MODULES=/nonexistent /Applications/HyperXTalk.app/Contents/MacOS/HyperXTalk`
> then run `encrypt "hello" using "blowfish" with password "world"`.
>
> `prebuilt/scripts/build-openssl.sh` already configures OpenSSL 3 with
> `no-module` (6035b6d3d) precisely so that the providers are compiled into
> libcrypto.a, but on macOS it was never used: its arm64 target name
> (`darwin-arm64-cc`) does not exist in OpenSSL, and `build-mac-extras.sh`
> overwrote the archives with Homebrew's anyway.
>
> Fix (PR to follow):
> - `build-mac-extras.sh` builds OpenSSL from source via `build-openssl.sh`
>   (`no-module`, so the legacy provider is built in, the build log shows
>   `-DSTATIC_LEGACY`) instead of copying Homebrew's archives, and refuses to
>   continue if the resulting libcustomcrypto.a has no
>   `ossl_legacy_provider_init`. `build-openssl.sh` gets the right arm64
>   target name. `make prebuilt-mac` in CI picks this up, so the next release
>   build is self-contained.
> - `mcssl.cpp` checks whether the legacy provider actually loaded, clears
>   the stale error so unrelated SSL calls do not report it, and when a
>   cipher cannot be initialised puts "cipher not available: the OpenSSL
>   legacy provider could not be loaded" in `the result` rather than failing
>   silently.
>
> With the rebuilt archive, Blowfish and AES both work with
> `OPENSSL_MODULES=/nonexistent`, and the engine no longer contains any
> `/opt/homebrew` path.
