# Team Roles Board

Source for the team board published as a Claude artifact:
https://claude.ai/artifact/2wuAWTJcXzBomHzKtV1YQS

Tabs: Tasks, Late rule, Accounts, Entry records, and an owner-only Access tab.

The page stores its data in the artifact's shared database (`window.claude` runtime),
so it only loads data when opened through the claude.ai link above. Opened anywhere
else (for example GitHub Pages), it shows the sign-in screen.
