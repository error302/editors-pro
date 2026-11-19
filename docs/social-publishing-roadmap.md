# Social sharing and direct publishing

Checked against primary developer sources on 1 November 2026.

## First delivery: share an exported video to another app

The completed-export screen offers YouTube, TikTok, Instagram, Facebook,
X, and More share options. Android app shortcuts are enabled only when
the installed app resolves a video sharing intent. The receiving app
controls its own editor, account selection, audience, and final publish
action. Some apps ignore the supplied caption; Copy caption lets the
user paste it there instead. More share options exposes the system chooser.

Opening another app is a handoff, not a publication receipt. The UI must
not say a video was posted, uploaded, or published based on an Android
intent or a `share_plus` result. The receiving app can cancel, reject the
format, require sign-in, or process the video before publication.

Android stages a unique copy in `cacheDir/social_share` before launching
`ACTION_SEND`. Only that cache subdirectory is exposed through a
non-exported FileProvider. The completed original is never moved,
overwritten, or deleted. A read-only URI grant and ClipData accompany the
intent. Temporary copies remain available while the receiver reads them;
Android may reclaim these cache files. Other platforms use `share_plus`
for the generic chooser. No app secret or social account token is required.

Primary source: [Android: sending data to other apps](https://developer.android.com/develop/ui/compose/sharing/send).

## Later delivery: authorized direct publishing

Each destination needs its own developer registration, OAuth consent,
account eligibility checks, upload implementation, and result tracking.
The user must select the destinations, review the target accounts and
metadata, then explicitly publish. Export completion alone must not
trigger a post. Enabling one provider does not enable another.

| Destination | Integration and eligibility | Important boundaries |
| --- | --- | --- |
| YouTube | Enable YouTube Data API and obtain a channel owner's OAuth grant for `youtube.upload`. Use `videos.insert` with resumable upload support. | Allow title, description, public/private/unlisted selection and destination selection. Track video processing after upload. Google OAuth verification may apply to sensitive scopes; additional quota requests require a YouTube compliance audit. The current insert reference says unverified API projects are **not** restricted to private viewing, unlike historical documentation. Confirm the current project configuration during integration. |
| TikTok | Register an app with Content Posting API and obtain app approval plus user authorization for `video.publish`. Query fresh creator information before the posting screen. | Direct Post needs an audit to remove unaudited-client private-only restrictions. Require explicit privacy choice, account display, interaction controls and appropriate music/commercial disclosures. Observe creator-specific duration and posting limits. Public content undergoes moderation; completion time is not guaranteed. The separate `video.upload` scope sends a draft for the creator to finish inside TikTok. |
| Instagram | Professional account (Business or Creator). Instagram Login uses `instagram_business_basic` and `instagram_business_content_publish`. Facebook Login uses a linked Page and a different permission family including `instagram_basic`, `instagram_content_publish`, and `pages_read_engagement`. | Create a media container from publicly retrievable media, wait until ready, then call `media_publish`. Ordinary consumer accounts are not eligible for this publishing API. Confirm external-customer app review, business verification, supported placements and current publishing limits before production rollout. |
| Facebook | Page publishing uses a Page access token. The official Reel sequence starts a session, uploads the video, then finishes with a supported publication state. | Build for Pages; retain app sharing for personal-profile workflows. Confirm the current `pages_manage_posts` permission and its dependencies, Page tasks, external-customer review/access requirements and current limits before production rollout. An uploaded file is not evidence that a Reel is published. |
| X | Register a developer app and obtain user-context OAuth authorization. Use `tweet.read`, `tweet.write`, `users.read`, `media.write`, and optionally `offline.access` when refresh is needed. | Initialize, append, finalize and await media processing before creating the post with its media ID. Current developer access uses usage credits; check live pricing and account limits rather than embedding commercial assumptions in the app. Video eligibility also depends on the posting account and media category. |

### Primary references

- YouTube: [insert and scopes](https://developers.google.com/youtube/data/reference/rest/v3/videos/insert), [resumable uploads](https://developers.google.com/youtube/v3/guides/using_resumable_upload_protocol), [minimum upload UX](https://developers.google.com/youtube/terms/required-minimum-functionality), [video processing](https://developers.google.com/youtube/data/reference/rest/v3/videos#processingDetails), [OAuth verification](https://developers.google.com/identity/protocols/oauth2/production-readiness/sensitive-scope-verification), [quota audits](https://developers.google.com/youtube/v3/guides/quota_and_compliance_audits).
- TikTok: [Direct Post prerequisites](https://developers.tiktok.com/docs/en/content-posting-api-get-started), [Direct Post API](https://developers.tiktok.com/docs/en/content-posting-api-reference-direct-post), [required sharing UX and audit restrictions](https://developers.tiktok.com/docs/en/content-sharing-guidelines), [draft upload](https://developers.tiktok.com/docs/en/content-posting-api-get-started-upload-content), [status and moderation](https://developers.tiktok.com/docs/en/content-posting-api-reference-get-video-status).
- Instagram: [Meta's official Postman collection](https://www.postman.com/meta/instagram/documentation/6yqw8pt/instagram-api), [content publishing reference](https://developers.facebook.com/docs/instagram-platform/content-publishing), [platform overview](https://developers.facebook.com/docs/instagram-platform/overview/).
- Facebook: [Meta's Page discovery/token example](https://www.postman.com/meta/facebook/request/bqfxwbp/get-access-tokens-of-pages-you-manage), [Reel creation](https://www.postman.com/meta/facebook/request/rgkn91u/1-create-reel), [Reel publishing](https://www.postman.com/meta/facebook/request/juhnm3q/4-publish-reel), [Reels guide](https://developers.facebook.com/docs/video-api/guides/reels-publishing/), [permissions reference](https://developers.facebook.com/docs/permissions).
- X: [OAuth PKCE and scopes](https://docs.x.com/fundamentals/authentication/oauth-2-0/authorization-code), [chunked video upload](https://docs.x.com/x-api/media/quickstart/media-upload-chunked), [create post](https://docs.x.com/x-api/posts/create-post), [pricing](https://docs.x.com/x-api/getting-started/pricing), [rate limits](https://docs.x.com/x-api/fundamentals/rate-limits).

**Meta documentation access boundary:** Meta's developer documentation
repeatedly returned HTTP 429 or could not be fetched during this audit.
The readable official Meta Postman collections establish the login/scope,
account and upload/publish flows cited above. Exact current numerical
Instagram/Facebook caps and external-customer App Review/Business
Verification rules were not independently verified from accessible
primary pages. Resolve those requirements against the live app dashboard
and developer documentation before enabling direct publishing. A test
with an app-role account does not establish customer production access.

## Publishing architecture and release evidence

Use an authenticated backend for provider callbacks, secret handling,
encrypted account tokens, temporary media hosting and background upload
jobs. Use OAuth state and PKCE where supported, narrow permissions,
revocation, expiry/refresh handling, and account-disconnect/data-deletion
flows. Never embed confidential app secrets in an APK or save provider
account tokens in the project's Drift database.

Persist nonsecret job metadata and provider IDs so work can recover after
app closure. Each destination has independent states: queued, uploading,
processing, published, needs action, or failed. Apply bounded retries to
safe transient operations, respect provider backoff, and reconcile an
ambiguous response against the saved upload/container/post ID before
retrying a publish operation. A timeout must not produce duplicate posts.
Display actual provider post links after confirmed publication; handoff,
transfer, processing, privacy, moderation and public visibility are
separate outcomes.

Release each adapter only after a real exported video has passed an
authorized account workflow, cancellation/revocation, failure/retry,
media validation and published-result verification. Unit tests, API
approval and successful uploads each provide useful but distinct evidence.

## High frame rate delivery

Keep the editor's 120 fps master separate from each destination's accepted delivery format. TikTok's [current Content Posting API media requirements](https://developers.tiktok.com/docs/en/content-posting-api-media-transfer-guide) specify 23-60 fps, so a future TikTok API adapter must validate/re-export at an accepted rate before upload. The current app-sharing flow hands off the selected exported file; processing in the receiving app is outside Editors Pro's control. Export help recommends 60 fps or lower for TikTok.

YouTube [recommends preserving the recorded frame rate](https://support.google.com/youtube/answer/1722171?hl=en) and lists 24/25/30/48/50/60 as common rates while accepting others. Do not assume that an accepted upload establishes its eventual playback rate. Re-check each provider's current media constraints before implementing direct publishing.
