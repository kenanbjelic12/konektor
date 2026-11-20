# Konektor

Upload and download your files between all your devices, using your own
Hostinger web hosting as the cloud. Runs on Windows and Android from one
Flutter codebase (iOS can follow).

This first version is manual: you press **Upload** to send files to your
hosting and **Download** to save a file to a folder you choose. There is no
automatic syncing yet.

## How it works

```
Konektor app (Windows)  ──HTTPS + secret token──▶  api.php on Hostinger  ──▶  ~/konektor-files/
```

- `server/api.php` is a small PHP script that lists, receives, sends and
  deletes files. Every request must carry your secret token.
- Files are kept in `konektor-files`, a folder in your Hostinger home
  directory **next to** `public_html`, so nobody can open them from a browser.

## 1. Set up the server on Hostinger (once)

1. Open **hPanel → Files → File Manager**.
2. Inside `public_html`, create a folder named `konektor`.
3. Upload these three files from the `server` folder of this repo into
   `public_html/konektor`: `api.php`, `.htaccess`, `config.example.php`.
4. Rename `config.example.php` to `config.php`, open it, and replace
   `CHANGE_ME_to_a_long_random_secret` with a long random password
   (at least 24 characters, letters and digits). This is your **token**.
   Keep it private; anyone with it can read your files.
5. Check it works: open `https://YOURDOMAIN/konektor/api.php?action=list` in a
   browser. You should see `{"error":"Wrong token"}`. That means the API is
   running and refusing visitors without the token.

**Upload size limit:** the `.htaccess` asks PHP for up to 512 MB per file.
If big uploads fail, raise *upload_max_filesize* and *post_max_size* in
**hPanel → Advanced → PHP Configuration → PHP options**.

## 2. Get the Windows app

**Easiest:** every push to `main` builds the app on GitHub. Open the repo's
**Actions** tab, click the latest *Build Windows app* run, download the
**Konektor-windows** artifact, unzip it anywhere, and run `konektor.exe`.

**Or build it yourself** (needs [Flutter](https://docs.flutter.dev/get-started/install/windows/desktop)
and Visual Studio with the *Desktop development with C++* workload):

```powershell
flutter pub get
flutter run -d windows            # try it
flutter build windows --release   # app ends up in build\windows\x64\runner\Release
```

## 2b. Get the Android app

Every push to `main` also builds `Konektor.apk` and attaches it to the
**latest** release: open the repo's **Releases** page on your phone (signed in
to GitHub), download `Konektor.apk`, and open it. Android asks you to allow
installing apps from your browser the first time.

On the phone, **Download** saves files to `Download/Konektor`. On older phones
(Android 10 and below) it shows a "save as" screen instead.

The APK is signed with a temporary key, so installing a newer build may ask
you to uninstall the old one first. To avoid that, add two repository
secrets, `ANDROID_KEYSTORE_BASE64` (a base64-encoded keystore with key alias
`konektor`) and `ANDROID_KEYSTORE_PASSWORD`, and the build will use them.

## 3. First run

The app asks for:

- **Server address:** `https://YOURDOMAIN/konektor`
- **Token:** the value you put in `config.php`

It checks the connection and remembers both on that computer. You can change
them later with the gear button. Install the app on each PC, enter the same
address and token, and they all see the same files.

## Project layout

| Path | What it is |
| --- | --- |
| `lib/main.dart` | App start: shows setup or the file list |
| `lib/screens/files_screen.dart` | File list with Upload, Download, Delete |
| `lib/screens/setup_screen.dart` | Server address and token form |
| `lib/services/storage_service.dart` | Talks to `api.php` (streams uploads and downloads) |
| `lib/services/settings.dart` | Saves settings on the device |
| `server/` | The PHP API for Hostinger |
| `.github/workflows/windows.yml` | Builds the Windows app on GitHub |

## Next ideas

- Folders, and uploading by drag and drop
- iOS build from the same code
- Automatic sync of a chosen folder
