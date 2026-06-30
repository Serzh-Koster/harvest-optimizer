@echo off
cd /d "%~dp0"
powershell -NoProfile -ExecutionPolicy Bypass -File ".\scripts\make-gallery.ps1"
start "" "%~dp0gallery.html"
