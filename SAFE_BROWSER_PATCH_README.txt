WSID SMM PANEL V30 — SAFE BROWSER FINAL PATCH

Changes intentionally limited to deployment/security hardening:
1. Removed the redundant unpkg.com Supabase fallback from index.html.
2. Added vercel.json security headers (HSTS, CSP, X-Content-Type-Options, X-Frame-Options, Referrer-Policy, Permissions-Policy).

Existing panel logic, Telegram dual notification + quote formatting, Supabase logic, admin logic, deposit/order functions, and UI files are otherwise unchanged.

IMPORTANT: Google Safe Browsing warnings are reputation/classification decisions outside the source code. This patch reduces unnecessary external surface and hardens the deployment, but no source ZIP can guarantee immediate removal of a Safe Browsing warning. If Chrome still shows “Situs berbahaya” after redeploy, the site owner must check Google Search Console / Safe Browsing status and request review after confirming the deployed site is clean.
