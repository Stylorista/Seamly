param(
  [string]$ApiBaseUrl = "http://127.0.0.1:8000",
  [string]$GoogleWebClientId = $env:GOOGLE_WEB_CLIENT_ID
)

# Builds the Flutter web app into dist/ for Firebase Hosting.
# Pass the live backend URL when you redeploy for production, e.g.:
#   powershell -File build_web.ps1 -ApiBaseUrl "https://seamly-backend.duckdns.org" -GoogleWebClientId "YOUR_ID.apps.googleusercontent.com"
flutter build web --release --output dist --dart-define=API_BASE_URL=$ApiBaseUrl --dart-define=GOOGLE_WEB_CLIENT_ID=$GoogleWebClientId