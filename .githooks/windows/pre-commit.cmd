@echo off
setlocal EnableExtensions
set "NB_ROOT_FILE=%TEMP%\niobium-hook-%RANDOM%.txt"
git rev-parse --show-toplevel > "%NB_ROOT_FILE%" || exit /b 1
set /p NB_ROOT=<"%NB_ROOT_FILE%" || exit /b 1
del /q "%NB_ROOT_FILE%"
cd /d "%NB_ROOT%" || exit /b 1
zig build hooks:pre-commit
exit /b %ERRORLEVEL%
