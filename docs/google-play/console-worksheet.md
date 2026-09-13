# ProxySmith Play Console worksheet

Use this as a drafting aid. Confirm every answer against the final uploaded app and Google Play's current form wording.

## Release artifact

- Upload artifact: `app/release/proxysmith-2.4.0-1-play.aab`
- Package: `ir.proxysmith.proxysmith_flutter`
- Version name: `2.4.0`
- Version code: `1`
- Minimum Android API: 24
- Target Android API: 36
- Play App Signing: Enroll on the first upload and retain the existing upload key securely

## App content draft

- App or game: App
- Category: Tools
- Ads: No
- App access: No login or restricted account is required
- Target audience: Adults; not designed for children
- News app: No
- Government app: No
- Financial features: Donation links only; no in-app financial account or transaction service
- Health features: No

## Data Safety review

Observed implementation:

- no developer-operated application backend;
- no account system;
- no advertising, analytics, tracking, or crash-reporting SDK;
- settings and explicitly saved sources are stored locally;
- one-off subscription URLs and test results are not retained as history;
- user-initiated network traffic goes directly to subscription hosts, proxy endpoints, the selected test endpoint, and GitHub when checking for updates.

Do not answer the form from this summary alone. Review Google Play's definitions of collection, sharing, ephemeral processing, and user-initiated transfers. In particular, do not claim that all traffic is encrypted: the app permits HTTP endpoints and proxy configurations without transport security.

The app has no account, so the account-deletion requirement is not applicable. Users can delete saved sources in the app or clear all local data through Android settings.

## Foreground service declaration

- Type: `dataSync`
- Core purpose: A user explicitly starts a bounded subscription download and multi-round proxy measurement run that must continue while the app is backgrounded.
- User visibility: The service displays an ongoing notification while work is active.
- Start condition: Direct user action in the app.
- Stop condition: Completion, cancellation, failure, or the total pipeline timeout.
- Reviewer instructions: Start a run with a valid subscription, background the app, observe the persistent notification and progress, then stop the run or allow it to complete.

## Before submission

- [ ] Confirm the verified Play Console owner and supported registration country
- [ ] Confirm the permanent package name before the first upload
- [ ] Publish the privacy policy at an active public URL
- [ ] Add a public support email in Play Console
- [ ] Prepare icon, feature graphic, and credential-free screenshots
- [ ] Upload the AAB to Internal testing first
- [ ] Inspect Play-generated APKs and supported-device exclusions
- [ ] Smoke-test subscription fetch, background execution, stop, results, copy, and QR flows
- [ ] Complete the content-rating and foreground-service forms accurately
- [ ] Complete any closed-testing period required for the account
- [ ] Back up the upload keystore and credentials outside the repository
- [ ] Increase `versionCode` for every later upload
