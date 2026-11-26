# SiteLedger allowance pilot

This developer demo takes a technician's allowance from an offline queue to an audited payment and a project cost posting. The Flutter client targets Android and Windows. FastAPI serves both. The demo uses one CityCare project and Block A, with one account per designation. All amounts travel in integer paise.

## Run the service

From this folder with Python 3.9 or newer:

```sh
python3 -m venv .venv
. .venv/bin/activate
python -m pip install -r backend/requirements.txt
export SITELEDGER_DEMO_PASSWORD='local-demo-only'
python -m uvicorn backend.app:app --host 127.0.0.1 --port 8000
```

The service creates .siteledger/demo.sqlite on first launch. To start with an empty ledger, point SITELEDGER_DB at a new file before starting the service. The API contract and interactive request forms are available at http://127.0.0.1:8000/docs while running. Use synthetic receipts and a local development machine. All five demo roles share the configured password. Session tokens expire after an hour. Sign in again to resume a saved queue.

## Run the client

From the client directory with Flutter installed, run `flutter pub get`, then `flutter devices`. For an Android emulator run `flutter run -d <emulator-id>`. For Windows desktop run `flutter run -d windows` on a Windows development machine with Visual Studio C++ desktop tools. Android emulators reach the host service at 10.0.2.2. Windows defaults to loopback. Use `--dart-define=API_URL=https://your-test-service` when the service runs on a different host. Local HTTP on Android is configured for debug builds.

1. Start with an empty demo database. Sign in online as Technician. Disconnect the network, enter three days at ₹400, fill in the expense date and particulars, and attach a PDF, PNG or JPEG up to 2 MiB. Save to the offline queue. The client stores the receipt bytes with the claim.
2. Reconnect, sign back in if the app restarted, and select **Sync saved claims**. The same client UUID is reused until the server acknowledges the claim. Expand its EXP entry to see the current reviewer and history.
3. Switch to Supervisor and approve. Switch to Site Engineer and approve. For amounts above ₹10,000 also sign in as Project Manager and approve.
4. Sign in as Head Office, mark the claim payable, then enter the payment date and reference. The server saves payment, audit event and Site overhead posting in one transaction.
5. Refresh on the other client. For this example the comparison changes from zero postings to one posting of ₹1,200. The original quotation carries zero under Site overhead. The demo records cost without enforcing an overhead budget pending management's decision.

## Verification

From the root, install `httpx==0.28.1` into the test environment and run `python -m unittest discover -s backend -v`. From client run `flutter analyze` and `flutter test`. The API tests exercise the real routes with an isolated database. The outbox test closes and reopens SQLite and simulates a lost acknowledgment.

## Pilot boundaries

This milestone supports positive allowances with zero GST, one receipt and the approval-to-payment path. Sync and report refresh are manual. The service uses SQLite for local evaluation. Production delivery still requires PostgreSQL migrations, individual identity and assignments, secure attachment storage, deployment and device acceptance. Other expense categories, returns, quotations, material control and client billing belong to later milestones. The acceptance folder retains the wider business examples.
