# Anime Portal UI redesign

This `lib/` folder is a UI-focused redesign based on the supplied Neo/UI reference.

## Included
- Neo dark navy visual system with cyan / violet / pink accents.
- Responsive layouts for phone, tablet and desktop widths.
- Redesigned Home, Series, Movies, Search, Playlist/Episodes, Profile, Login and Sign-up screens.
- Redesigned video-player entry screen while keeping the existing playback/data methods.
- Admin/upload/manage screens receive the new palette without changing their data workflows.
- Dependency-free 3D-style animated splash screen using Flutter `Transform`/`Matrix4`.
- No new package dependency was added.

## Important
The supplied archive contained only `lib/`, not `pubspec.yaml` or the Android/iOS project folders. Therefore the final Flutter project was not buildable in this environment and a real `flutter analyze` / `flutter build` could not be executed here. The changes were checked with static source/delimiter validation and kept to the existing package/API surface.

Replace the existing project's `lib/` with this folder and run:

```bash
flutter pub get
flutter analyze
flutter run
```
