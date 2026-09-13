---
title: ProxySmith Privacy Policy
permalink: /privacy-policy/
---

# ProxySmith Privacy Policy

Effective date: September 13, 2026

ProxySmith is an open-source utility that downloads proxy subscription data selected by the user, tests supported proxy configurations on the user's device, and ranks the results. This policy describes the Android app published under the package name `ir.proxysmith.proxysmith_flutter`.

## Data collected by the developer

ProxySmith does not require an account and does not include advertising, analytics, crash-reporting, or tracking SDKs. The developer does not operate an application server that receives subscription URLs, proxy credentials, test results, or usage history.

## Data stored on the device

ProxySmith stores the user's theme, language, selected source, test count, latency limit, concurrency setting, test endpoint, and any subscription sources the user explicitly saves. This information remains in the app's local storage. Tested proxy results and one-off subscription URLs are not retained as result history.

Users can remove saved custom sources in the app. Android's app settings can clear all local app data, and uninstalling ProxySmith removes its local data. Content copied by the user is managed separately by the Android clipboard.

## Network activity

When the user starts a test, ProxySmith:

- contacts the selected subscription URL to download its contents;
- connects to proxy servers contained in that subscription;
- sends test requests to the test endpoint selected by the user; and
- processes the returned measurements locally on the device.

The selected subscription provider, proxy operators, test endpoint operator, internet provider, and other network intermediaries may receive network metadata under their own policies. Subscription URLs and proxy links can contain credentials. Users should use sources and endpoints they trust. Transport security depends on the URL and proxy configuration selected by the user; ProxySmith accepts both HTTP and HTTPS endpoints.

ProxySmith contacts GitHub's public API only when the user selects **Check for updates**. Feedback, donation, and release-page links open external applications or websites only when the user selects them. Those services apply their own privacy policies.

## Sharing

ProxySmith does not sell personal information. The developer does not receive or share user data through the app. Network communications initiated by the user are sent directly to the third-party services and proxy endpoints described above.

## Children

ProxySmith is a technical networking utility and is not directed to children.

## Changes to this policy

Material changes will be published on this page with a revised effective date.

## Contact

Questions or privacy requests can be submitted through the [ProxySmith issue tracker](https://github.com/soroushyasini/proxysmith/issues). Do not include subscription URLs, proxy credentials, or other secrets in a public issue.
