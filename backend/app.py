"""SiteLedger local demonstration service. Monetary values are integer paise."""
import base64
import hashlib
import json
import os
import secrets
import sqlite3
from contextlib import contextmanager
from datetime import date
from pathlib import Path
from time import time
from uuid import UUID

from fastapi import Depends, FastAPI, Header, HTTPException
from pydantic import BaseModel, Field
from typing import Literal

app = FastAPI(title="SiteLedger allowance demo", version="0.1")
ROLES = ("technician", "supervisor", "siteengineer", "pm", "headoffice")
PROJECT = "CityCare Block A electrification"
BUILDING = "Block A"
SCHEMA = """
CREATE TABLE IF NOT EXISTS sessions(token TEXT PRIMARY KEY, actor TEXT NOT NULL, expires INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS claims(
 id INTEGER PRIMARY KEY, client_id TEXT UNIQUE NOT NULL, owner TEXT NOT NULL, digest TEXT NOT NULL,
 details TEXT NOT NULL, amount INTEGER NOT NULL, status TEXT NOT NULL, reviewer TEXT, version INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS events(claim INTEGER REFERENCES claims, version INTEGER, actor TEXT,
 action TEXT, at TEXT DEFAULT CURRENT_TIMESTAMP, PRIMARY KEY(claim,version));
CREATE TABLE IF NOT EXISTS payments(claim INTEGER PRIMARY KEY REFERENCES claims, paid_on TEXT, reference TEXT);
CREATE TABLE IF NOT EXISTS postings(claim INTEGER PRIMARY KEY REFERENCES payments, project TEXT, building TEXT,
 head TEXT, amount INTEGER CHECK(amount>0));
"""


@contextmanager
def transaction():
    path = Path(os.environ.get("SITELEDGER_DB", ".siteledger/demo.sqlite"))
    path.parent.mkdir(parents=True, exist_ok=True)
    db = sqlite3.connect(path, timeout=10)
    db.row_factory = sqlite3.Row
    try:
        db.execute("PRAGMA foreign_keys=ON")
        db.execute("BEGIN IMMEDIATE")
        yield db
        db.commit()
    finally:
        db.close()


@app.on_event("startup")
def initialize():
    with transaction() as db:
        db.executescript(SCHEMA)


class Login(BaseModel):
    account: str
    password: str


@app.post("/v1/login")
def login(data: Login):
    password = os.environ.get("SITELEDGER_DEMO_PASSWORD", "")
    if not password or data.account not in ROLES or not secrets.compare_digest(
        data.password.encode(), password.encode()
    ):
        raise HTTPException(401, "Invalid demo credentials")
    token = secrets.token_urlsafe(32)
    with transaction() as db:
        db.execute("INSERT INTO sessions VALUES(?,?,?)",
                   (hashlib.sha256(token.encode()).hexdigest(), data.account, int(time()) + 3600))
    return {"token": token}


def current_actor(authorization: str = Header(default="")):
    token = authorization.removeprefix("Bearer ")
    with transaction() as db:
        row = db.execute("SELECT actor FROM sessions WHERE token=? AND expires>?",
                         (hashlib.sha256(token.encode()).hexdigest(), int(time()))).fetchone()
    if not row:
        raise HTTPException(401, "Sign in to sync or review claims")
    return row["actor"]


class Allowance(BaseModel):
    client_id: UUID
    project: Literal["CityCare Block A electrification"]
    building: Literal["Block A"]
    expense_date: date
    kind: Literal["Daily", "Food", "Conveyance"]
    days: int = Field(strict=True, ge=1, le=366)
    rate_paise: int = Field(strict=True, ge=1, le=100000000)
    description: str = Field(min_length=1, max_length=500, pattern=r"\S")
    filename: str = Field(min_length=1, max_length=255)
    receipt: str = Field(min_length=4, max_length=2796204)


def detail(db, row):
    data = json.loads(row["details"])
    data.pop("receipt")
    payment = db.execute("SELECT paid_on,reference FROM payments WHERE claim=?", (row["id"],)).fetchone()
    data["payment"] = dict(payment) if payment else None
    return dict(data, number=f"EXP-{row['id']:04d}", id=row["id"], amount=row["amount"],
                status=row["status"], reviewer=row["reviewer"], version=row["version"],
                history=[dict(e) for e in db.execute(
                    "SELECT actor,action,at FROM events WHERE claim=? ORDER BY version", (row["id"],))])


@app.post("/v1/claims")
def submit(data: Allowance, actor=Depends(current_actor)):
    if actor != "technician":
        raise HTTPException(403, "Only the assigned technician can submit this allowance")
    try:
        receipt = base64.b64decode(data.receipt, validate=True)
    except ValueError:
        raise HTTPException(422, "Invalid receipt encoding")
    if len(receipt) > 2097152 or not receipt.startswith((b"%PDF-", b"\xff\xd8\xff", b"\x89PNG\r\n\x1a\n")):
        raise HTTPException(422, "Attach a PDF, JPEG or PNG up to 2 MiB")
    payload = data.model_dump_json()
    digest = hashlib.sha256(payload.encode()).hexdigest()
    key = str(data.client_id)
    with transaction() as db:
        row = db.execute("SELECT * FROM claims WHERE client_id=?", (key,)).fetchone()
        if row is None:
            cursor = db.execute("INSERT INTO claims(client_id,owner,digest,details,amount,status,reviewer,version) "
                                "VALUES(?,?,?,?,?,'Submitted','supervisor',1)",
                                (key, actor, digest, payload, data.days * data.rate_paise))
            db.execute("INSERT INTO events(claim,version,actor,action) VALUES(?,1,?,'Submit')",
                       (cursor.lastrowid, actor))
            row = db.execute("SELECT * FROM claims WHERE id=?", (cursor.lastrowid,)).fetchone()
        elif row["digest"] != digest or row["owner"] != actor:
            raise HTTPException(409, "Submission key already used for a different claim")
        return detail(db, row)


@app.get("/v1/claims")
def claims(actor=Depends(current_actor)):
    with transaction() as db:
        return [detail(db, row) for row in db.execute(
            "SELECT * FROM claims WHERE ? != 'technician' OR owner=? ORDER BY id DESC", (actor, actor))]


@app.get("/v1/claims/{claim}/receipt")
def evidence(claim: int, actor=Depends(current_actor)):
    with transaction() as db:
        row = db.execute("SELECT details FROM claims WHERE id=? AND (? != 'technician' OR owner=?)",
                         (claim, actor, actor)).fetchone()
        if not row:
            raise HTTPException(404)
        stored = json.loads(row["details"])
        return {"receipt": stored["receipt"]}


class Decision(BaseModel):
    version: int
    action: Literal["Approve", "Mark payable", "Pay"]
    payment_date: date = None
    reference: str = Field(default="", max_length=100)


@app.post("/v1/claims/{claim}/decision")
def decide(claim: int, data: Decision, actor=Depends(current_actor)):
    with transaction() as db:
        row = db.execute("SELECT * FROM claims WHERE id=?", (claim,)).fetchone()
        if not row:
            raise HTTPException(404)
        reference = data.reference.strip()
        if row["status"] == "Paid" and actor == "headoffice" and data.action == "Pay":
            payment = db.execute("SELECT * FROM payments WHERE claim=?", (claim,)).fetchone()
            if (payment["paid_on"], payment["reference"]) == (str(data.payment_date), reference):
                return detail(db, row)
        if row["version"] != data.version:
            raise HTTPException(409, "Claim changed. Refresh before deciding.")
        if row["reviewer"] != actor:
            raise HTTPException(403, "This decision belongs to another reviewer")
        status = row["status"]
        if status == "Submitted" and data.action == "Approve":
            route = ["supervisor", "siteengineer"]
            if row["amount"] > 1000000:
                route.append("pm")
            if actor == route[-1]:
                status, reviewer = "Approved", "headoffice"
            else:
                reviewer = route[route.index(actor) + 1]
        elif status == "Approved" and data.action == "Mark payable":
            status, reviewer = "Payable", "headoffice"
        elif status == "Payable" and data.action == "Pay":
            if not data.payment_date or not reference:
                raise HTTPException(422, "Enter payment date and reference")
            db.execute("INSERT INTO payments VALUES(?,?,?)", (claim, str(data.payment_date), reference))
            db.execute("INSERT INTO postings VALUES(?,?,?,'Site overhead',?)",
                       (claim, PROJECT, BUILDING, row["amount"]))
            status, reviewer = "Paid", None
        else:
            raise HTTPException(409, "Action is unavailable at this stage")
        db.execute("UPDATE claims SET status=?,reviewer=?,version=version+1 WHERE id=?", (status, reviewer, claim))
        db.execute("INSERT INTO events(claim,version,actor,action) VALUES(?,?,?,?)",
                   (claim, data.version + 1, actor, data.action))
        return detail(db, db.execute("SELECT * FROM claims WHERE id=?", (claim,)).fetchone())


@app.get("/v1/comparison")
def comparison(actor=Depends(current_actor)):
    with transaction() as db:
        row = db.execute("SELECT COUNT(*) AS postings, COALESCE(SUM(amount),0) AS actual_paise FROM postings").fetchone()
        return dict(row, project=PROJECT, building=BUILDING, cost_head="Site overhead", quoted_paise=0)
