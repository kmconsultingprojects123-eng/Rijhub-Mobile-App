/root/.pm2/logs/artisan-api-out.log last 15 lines:
0|artisan- |     }
0|artisan- | [2026-05-14 14:01:59.177 +0000] DEBUG (1938493): verifyJWT - incoming header
0|artisan- |     reqId: "req-2q"
0|artisan- | [2026-05-14 14:01:59.178 +0000] INFO (1938493): request completed
0|artisan- |     reqId: "req-2q"
0|artisan- |     res: {
0|artisan- |       "statusCode": 401
0|artisan- |     }
0|artisan- |     responseTime: 0.4823932647705078
0|artisan- | [2026-05-14 14:01:59.186 +0000] INFO (1938493): request completed
0|artisan- |     reqId: "req-2p"
0|artisan- |     res: {
0|artisan- |       "statusCode": 200
0|artisan- |     }
0|artisan- |     responseTime: 18.327157974243164

0|artisan-api  | [2026-05-14 14:02:10.172 +0000] INFO (1938493): incoming request
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  |     req: {
0|artisan-api  |       "method": "POST",
0|artisan-api  |       "url": "/api/auth/oauth/google",
0|artisan-api  |       "host": "rijhub.com",
0|artisan-api  |       "remoteAddress": "127.0.0.1",
0|artisan-api  |       "remotePort": 44556
0|artisan-api  |     }
0|artisan-api  | [2026-05-14 14:02:10.173 +0000] WARN (1938493): google token verify failed, retrying with token aud
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  | [2026-05-14 14:02:10.179 +0000] INFO (1938493): google oauth:user_created
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  |     email: "iamthecodemonk@gmail.com"
0|artisan-api  |     role: "customer"
0|artisan-api  | [2026-05-14 14:02:10.179 +0000] WARN (1938493): google oauth:device_token_missing
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  | [2026-05-14 14:02:10.179 +0000] INFO (1938493): google oauth:welcome_notification_start
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  |     email: "iamthecodemonk@gmail.com"
0|artisan-api  | [2026-05-14 14:02:10.179 +0000] INFO (1938493): notification:create:start
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  |     type: "welcome"
0|artisan-api  |     title: "Welcome to RijHub"
0|artisan-api  |     sendEmail: true
0|artisan-api  | [2026-05-14 14:02:10.180 +0000] INFO (1938493): notification:create:in_app_saved
0|artisan-api  |     notificationId: "6a05d5e26baae39e48480cb6"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  |     type: "welcome"
0|artisan-api  | [2026-05-14 14:02:10.181 +0000] INFO (1938493): notification:socket:emitted
0|artisan-api  |     notificationId: "6a05d5e26baae39e48480cb6"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  | [2026-05-14 14:02:10.181 +0000] INFO (1938493): notification:email:sending
0|artisan-api  |     notificationId: "6a05d5e26baae39e48480cb6"
0|artisan-api  |     to: "iamthecodemonk@gmail.com"
0|artisan-api  |     subject: "Welcome to RijHub"
0|artisan-api  | [2026-05-14 14:02:13.660 +0000] INFO (1938493): notification:email:sent
0|artisan-api  |     notificationId: "6a05d5e26baae39e48480cb6"
0|artisan-api  |     to: "iamthecodemonk@gmail.com"
0|artisan-api  | [2026-05-14 14:02:13.663 +0000] DEBUG (1938493): notification:fcm:skipped_no_tokens
0|artisan-api  |     notificationId: "6a05d5e26baae39e48480cb6"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  | [2026-05-14 14:02:13.663 +0000] INFO (1938493): google oauth:welcome_notification_done
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  |     userId: "6a05d5e26baae39e48480cb3"
0|artisan-api  |     email: "iamthecodemonk@gmail.com"
0|artisan-api  | [2026-05-14 14:02:13.666 +0000] INFO (1938493): request completed
0|artisan-api  |     reqId: "req-2r"
0|artisan-api  |     res: {
0|artisan-api  |       "statusCode": 200
0|artisan-api  |     }
0|artisan-api  |     responseTime: 3493.769434928894
0|artisan-api  | 6a05d5e26baae39e48480cb3
0|artisan-api  | 6a05d5e26baae39e48480cb3
0|artisan-api  | 6a05d5e26baae39e48480cb3
0|artisan-api  | [2026-05-14 14:02:14.704 +0000] INFO (1938493): incoming request
0|artisan-api  |     reqId: "req-2s"
0|artisan-api  |     req: {
0|artisan-api  |       "method": "GET",
0|artisan-api  |       "url": "/api/users/me",
0|artisan-api  |       "host": "rijhub.com",
0|artisan-api  |       "remoteAddress": "127.0.0.1",
0|artisan-api  |       "remotePort": 44572
0|artisan-api  |     }
0|artisan-api  | [2026-05-14 14:02:14.704 +0000] DEBUG (1938493): verifyJWT - incoming header
0|artisan-api  |     reqId: "req-2s"
0|artisan-api  |     authHeader: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjZhMDVkNWUyNmJhYWUzOWU0ODQ4MGNiMyIsInJvbGUiOiJjdXN0b21lciIsImlhdCI6MTc3ODc2NzMzMywiZXhwIjoxNzc5MzcyMTMzfQ.3ocXy3nipYLneCbkENdHOhMh4bkOIZCBhR5L48kJZh8"
0|artisan-api  | [2026-05-14 14:02:14.708 +0000] INFO (1938493): request completed
0|artisan-api  |     reqId: "req-2s"
0|artisan-api  |     res: {
0|artisan-api  |       "statusCode": 200
0|artisan-api  |     }
0|artisan-api  |     responseTime: 3.7844362258911133
0|artisan-api  | [2026-05-14 14:02:14.720 +0000] INFO (1938493): incoming request
0|artisan-api  |     reqId: "req-2t"
0|artisan-api  |     req: {
0|artisan-api  |       "method": "GET",
0|artisan-api  |       "url": "/api/users/me",
0|artisan-api  |       "host": "rijhub.com",
0|artisan-api  |       "remoteAddress": "127.0.0.1",
0|artisan-api  |       "remotePort": 44580
0|artisan-api  |     }
0|artisan-api  | [2026-05-14 14:02:14.720 +0000] DEBUG (1938493): verifyJWT - incoming header
0|artisan-api  |     reqId: "req-2t"
0|artisan-api  |     authHeader: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjZhMDVkNWUyNmJhYWUzOWU0ODQ4MGNiMyIsInJvbGUiOiJjdXN0b21lciIsImlhdCI6MTc3ODc2NzMzMywiZXhwIjoxNzc5MzcyMTMzfQ.3ocXy3nipYLneCbkENdHOhMh4bkOIZCBhR5L48kJZh8"
0|artisan-api  | [2026-05-14 14:02:14.724 +0000] INFO (1938493): request completed
0|artisan-api  |     reqId: "req-2t"
0|artisan-api  |     res: {
0|artisan-api  |       "statusCode": 200
0|artisan-api  |     }
0|artisan-api  |     responseTime: 3.8849573135375977
0|artisan-api  | [2026-05-14 14:02:14.736 +0000] INFO (1938493): incoming request
0|artisan-api  |     reqId: "req-2u"
0|artisan-api  |     req: {
0|artisan-api  |       "method": "GET",
0|artisan-api  |       "url": "/api/users/me",
0|artisan-api  |       "host": "rijhub.com",
0|artisan-api  |       "remoteAddress": "127.0.0.1",
0|artisan-api  |       "remotePort": 44582
0|artisan-api  |     }
0|artisan-api  | [2026-05-14 14:02:14.736 +0000] DEBUG (1938493): verifyJWT - incoming header
0|artisan-api  |     reqId: "req-2u"
0|artisan-api  |     authHeader: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjZhMDVkNWUyNmJhYWUzOWU0ODQ4MGNiMyIsInJvbGUiOiJjdXN0b21lciIsImlhdCI6MTc3ODc2NzMzMywiZXhwIjoxNzc5MzcyMTMzfQ.3ocXy3nipYLneCbkENdHOhMh4bkOIZCBhR5L48kJZh8"
0|artisan-api  | [2026-05-14 14:02:14.740 +0000] INFO (1938493): request completed
0|artisan-api  |     reqId: "req-2u"
0|artisan-api  |     res: {
0|artisan-api  |       "statusCode": 200
0|artisan-api  |     }
0|artisan-api  |     responseTime: 4.5839385986328125
0|artisan-api  | [2026-05-14 14:02:15.857 +0000] INFO (1938493): incoming request
0|artisan-api  |     reqId: "req-2v"
0|artisan-api  |     req: {
0|artisan-api  |       "method": "POST",
0|artisan-api  |       "url": "/api/devices/register",
0|artisan-api  |       "host": "rijhub.com",
0|artisan-api  |       "remoteAddress": "127.0.0.1",
0|artisan-api  |       "remotePort": 44586
0|artisan-api  |     }
0|artisan-api  | [2026-05-14 14:02:15.858 +0000] DEBUG (1938493): verifyJWT - incoming header
0|artisan-api  |     reqId: "req-2v"
0|artisan-api  |     authHeader: "Bearer eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpZCI6IjZhMDVkNWUyNmJhYWUzOWU0ODQ4MGNiMyIsInJvbGUiOiJjdXN0b21lciIsImlhdCI6MTc3ODc2NzMzMywiZXhwIjoxNzc5MzcyMTMzfQ.3ocXy3nipYLneCbkENdHOhMh4bkOIZCBhR5L48kJZh8"
0|artisan-api  | [2026-05-14 14:02:15.862 +0000] INFO (1938493): request completed
0|artisan-api  |     reqId: "req-2v"
0|artisan-api  |     res: {
0|artisan-api  |       "statusCode": 200
0|artisan-api  |     }
0|artisan-api  |     responseTime: 4.375039100646973
^C
root@server1:/var/www/api_rijhub/artisan#
device token is empty 
In-app notifications:
Call GET /api/notifications?unread=true after login.
The backend returns notifications in both response.data and response.notifications.
Use either one to display the notification list.

Push notifications:
For the welcome push notification to work during Google login, include the device FCM token inside POST /api/auth/oauth/google.

Example body:
{
  "idToken": "google_id_token",
  "role": "customer",
  "fcmToken": "firebase_device_token",
  "platform": "android"
}

Accepted token field names:
- fcmToken
- deviceToken
- notificationToken
- token

If the app calls POST /api/devices/register only after Google login, future push notifications will work, but the welcome push will be skipped because the backend had no token yet.