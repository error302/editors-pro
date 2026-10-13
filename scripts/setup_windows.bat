@echo off
setlocal
cd /d "%~dp0.."

echo EDITORS-PRO Android build prerequisites
echo.

where flutter >nul 2>&1 || goto :missing_flutter
where cargo >nul 2>&1 || goto :missing_cargo
where cargo-ndk >nul 2>&1 || goto :missing_cargo_ndk
where docker >nul 2>&1 || goto :missing_docker

echo Flutter, Rust, cargo-ndk, and Docker are available.
echo Start Docker Desktop, then run:
echo   powershell -ExecutionPolicy Bypass -File .\scripts\build_ffmpeg_android.ps1
echo   powershell -ExecutionPolicy Bypass -File .\scripts\build_android_release.ps1
echo.
echo The first FFmpeg build downloads the verified Android NDK and may take several minutes.
goto :done

:missing_flutter
echo Flutter is missing from PATH. Install Flutter and reopen this terminal.
goto :done

:missing_cargo
echo Rust and Cargo are missing from PATH. Install Rust from https://rustup.rs.
goto :done

:missing_cargo_ndk
echo cargo-ndk is missing. Install it with: cargo install cargo-ndk
goto :done

:missing_docker
echo Docker Desktop is required for the signed LGPL FFmpeg Android build.
goto :done

:done
pause
