import base64
import json
import os
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch
from uuid import uuid4

import httpx

from backend.app import app, initialize


class Workflow(unittest.IsolatedAsyncioTestCase):
    async def asyncSetUp(self):
        folder = tempfile.TemporaryDirectory()
        self.addCleanup(folder.cleanup)
        env = patch.dict(os.environ, SITELEDGER_DB=str(Path(folder.name) / "demo.sqlite"), SITELEDGER_DEMO_PASSWORD="test")
        env.start()
        self.addCleanup(env.stop)
        initialize()
        self.api = httpx.AsyncClient(transport=httpx.ASGITransport(app=app), base_url="http://demo")
        self.addAsyncCleanup(self.api.aclose)
        self.headers = {}
        for role in ("technician", "supervisor", "siteengineer", "pm", "headoffice"):
            session = await self.api.post("/v1/login", json={"account": role, "password": "test"})
            self.headers[role] = {"Authorization": "Bearer " + session.json()["token"]}

    def payload(self, days, rate):
        return dict(client_id=str(uuid4()), project="CityCare Block A electrification", building="Block A",
                    kind="Daily", expense_date="2026-11-25", days=days, rate_paise=rate, description="Site stay",
                    filename="voucher.pdf", receipt=base64.b64encode(b"%PDF-demo").decode())

    async def submit(self, payload):
        return await self.api.post("/v1/claims", json=payload, headers=self.headers["technician"])

    async def decision(self, claim, actor, action, **extra):
        return await self.api.post(f"/v1/claims/{claim['id']}/decision", headers=self.headers[actor],
                                   json=dict(action=action, version=claim["version"], **extra))

    async def comparison(self):
        return (await self.api.get("/v1/comparison", headers=self.headers["headoffice"])).json()

    async def test_allowance(self):
        fixture = json.loads((Path(__file__).resolve().parents[1] / "acceptance/commercial-cases.json").read_text())["allowance"]
        from decimal import Decimal
        payload = self.payload(fixture["days"], int(Decimal(fixture["rate"]) * 100))
        claim = (await self.submit(payload)).json()
        self.assertEqual(claim, (await self.submit(payload)).json())
        self.assertEqual((await self.submit(dict(payload, days=4))).status_code, 409)
        self.assertEqual((await self.decision(claim, "siteengineer", "Approve")).status_code, 403)
        for actor, action in [("supervisor", "Approve"), ("siteengineer", "Approve"), ("headoffice", "Mark payable")]:
            updated = (await self.decision(claim, actor, action)).json()
            self.assertEqual((await self.decision(claim, actor, action)).status_code, 409)
            claim = updated
        self.assertEqual((await self.comparison())["actual_paise"], 0)
        self.assertEqual((await self.decision(claim, "headoffice", "Pay")).status_code, 422)
        for _ in range(2):
            paid = (await self.decision(claim, "headoffice", "Pay", payment_date="2026-11-25", reference="TEST-001")).json()
            self.assertEqual(paid["status"], "Paid")
            self.assertEqual(len(paid["history"]), 5)
        totals = await self.comparison()
        self.assertEqual(totals["postings"], fixture["expected_posting_count"])
        self.assertEqual(totals["actual_paise"], int(Decimal(fixture["expected_actual_after_payment_retry"])*100))

    async def test_boundaries_and_scope(self):
        self.assertEqual((await self.api.get("/v1/claims")).status_code, 401)
        for rate, next_reviewer in [(1000000, "headoffice"), (1000001, "pm")]:
            payload = self.payload(1, rate)
            self.assertEqual((await self.submit(dict(payload, project="Other project"))).status_code, 422)
            claim = (await self.submit(payload)).json()
            for actor in ["supervisor", "siteengineer"]:
                claim = (await self.decision(claim, actor, "Approve")).json()
            self.assertEqual(claim["reviewer"], next_reviewer)
