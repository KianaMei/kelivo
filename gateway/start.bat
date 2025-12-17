@echo off
set CORS_ALLOW_ORIGINS=http://localhost:3000
echo Starting Gateway with CORS_ALLOW_ORIGINS=%CORS_ALLOW_ORIGINS%
gateway.exe