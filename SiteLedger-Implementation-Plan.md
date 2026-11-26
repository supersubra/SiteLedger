# SiteLedger software preparation and implementation plan

Company A needs to answer three questions for each electrical contracting job. What did the field team spend? How does that compare with the approved quotation? How much completed work can Head Office bill? Build one Flutter application for Android and Windows, backed by one API and one authoritative database. Deliver the first working slice from an offline allowance claim through payment to the updated comparison. Then add the measurement-to-bill workflow against the same project breakdown.

**Source of requirements.** [SiteLedger assignment prompt](SiteLedger%20-%20Assignment%20Prompt.docx). The Windows desktop app is the office frontend. The Android app is the field frontend. A browser client would be a separate delivery decision. The technology choices beyond Flutter and the accounting conventions identified below are proposed implementation decisions.

## 1. People, scope and ownership

| User | Home screen and permitted work |
| --- | --- |
| Technician | Own claims and their status. File expenses and daily notes against assigned projects. Save a claim offline. |
| Supervisor | Assigned project progress, pending measurements, tools out and open claims. Review technician claims, record measurements, issue and return tools, and capture own claims offline. |
| Site Engineer | Building work queue. Review claims, submit measured quantities and request tool rentals. Small ordinary claims finish operational review here. |
| Project Manager (PM) | Assigned projects, certified progress, cost versus quotation, bills raised and pending decisions. Review larger claims and tool rentals, approve variations at the first stage and certify measurements. |
| Head Office (HO) | All projects, payment queue, draft bills and overruns. Maintain masters, approve quotations, give final variation approval, mark claims payable and paid, issue bills and record client receipts. |
| Approved contractor | Only assigned subcontract packages, measurements on those packages and own invoice/payment status. Contractor invoices belong to subcontract accounting. |

Give each account one primary role. Scope employees by project assignment and contractors by package assignment. Apply the same checks to searches, totals, exports, files and direct record lookups. A role controls the action a person may take. An assignment controls the records on which they may take it.

## 2. Application architecture

| Component | Proposed implementation | Responsibility |
| --- | --- | --- |
| Android and Windows | Flutter/Dart, shared feature modules, responsive layouts | One sign-in model, shared field validation, date and INR formatting, role-aware navigation and platform-specific capture/print adapters. |
| Local storage | SQLite behind a client repository | Persist drafts, attachment references, cached project choices and a durable submission queue. Partition by account. Keep files in private application storage. |
| Backend | Python/FastAPI modular service with versioned JSON endpoints | Own authorization, approval routing, costing, certification, numbering and transactions. Publish an API contract for both builds. |
| Shared data | PostgreSQL and versioned migrations | Maintain project masters, commercial history, workflow records, ledger postings and report queries. All connected devices read the same committed state. |
| Attachments | Private object storage plus metadata in PostgreSQL | Handle bill photos and PDFs, verify uploads and authorize downloads. Keep server files independent of device paths. |
| Delivery | Separate development, test and production environments | Package a signed Android build and a Windows installer. Build and test Windows on a Windows runner. Keep keys and demo data out of production images. |

Organize the client by identity, masters, quotations, claims, tools, actuals, measurements, billing and reporting. Split each feature into screens, application logic and data access. Put financial rules in backend services and share calculation fixtures with Flutter for previews. Prefer transactional SQL views for the initial comparison and dashboard so a payment appears as soon as its transaction commits.

## 3. Frontend and mobile design

**Shared presentation.** Use the SiteLedger name, a light background, deep blue primary actions and status chips with readable text. Format INR to two decimal places and dates as DD-MMM-YYYY. Branch layouts on available width. Test both apps at phone and laptop widths. Use vertically stacked forms and cards at narrow widths, tables and split views at wider widths. Keep keyboard navigation, accessible labels, validation beside each field and a visible pending state during submission.

| Area | Android field experience | Windows office experience |
| --- | --- | --- |
| Home and navigation | Large tap targets and bottom navigation for Home, Claims, Measurements and Tools as permitted. Provide a route to read-only Comparison. | Left navigation for Dashboard, Projects and breakdown, Quotation and variations, Claims and payment, Material and attendance, Comparison, Measurements and part bills, Tools and Masters. |
| Expense entry and review | New claim, camera/file picker, local draft, sync status and My claims. Show the current reviewer and any return remark. | Filter the approval and payment queues by project, status and age. Open the claim beside its documents and approval history. Require payment date and reference. |
| Site operations | Record daily notes, issue/return tools, prepare measurement lines and review certified progress. Make building and unit visible at entry. | Edit masters and project structure, enter materials and attendance, certify quantities and investigate source records. |
| Commercial controls | Show quoted, committed, actual, billed and available balances as stacked cards with status text. Contractor screens show only assigned work. | Editable quotation and variation grids, certification detail, part-bill preview, project control panel and print-ready comparison with active filters and reporting date. |

Use the same claim detail order on both devices. Show the EXP number, project, building, claimant, role and date first. Follow with type, particulars and amount per line, attachment list, approval grid (step, approver, action, date, remark) and running status. Show unsynced records with a local identifier until the server assigns an EXP number.

### Offline claim lifecycle

1. Download authorized project, building, tool and expense choices while signed in. Show when the cache was refreshed.
2. On save, generate a client UUID, copy attachments into app-private storage and commit the draft and its file references locally. On Submit, freeze that version and enqueue it in the same SQLite transaction. Display **Waiting to sync**.
3. On reconnect or manual retry, refresh credentials, resume uploads, verify file references and submit with the original UUID and payload version. The server rechecks assignment, project and required fields. A unique submission key returns the prior result if acknowledgment was lost.
4. Replace the pending badge with the server number, status and timestamp only after acknowledgment. Retain failed drafts and explain the corrective action for revoked access, missing files or stale fields. Retry transient failures with backoff. Keep queued data isolated when users switch accounts.
5. Keep approvals, payments, certification and issue online so each decision sees current authority and balances. Test network loss before upload, after upload, after server commit and across device restart.

## 4. Backend workflows and business rules

### Masters, quotation and variation

HO manages customers, locations, buildings, employees, approved contractors and tools. Each location contains buildings. A project represents one customer order across one or more buildings. Capture scope, start/end dates, status (Draft, Active, On hold, Completed), retention rate and breakdown depth. Use editable package and sub-head names. A two-level project carries quantity, unit and rate on the sub-head. A three-level project carries them on its BOQ leaf. Lock structural changes that would invalidate approved or posted lines.

Create one original quotation per project and preserve revisions. Each line identifies its leaf, description, cost head (Material, Direct labor or Subcontract labor), unit, quantity, rate, amount and GST rate (default 18%). Allow Draft → Submitted → Approved. Approve a revision and supersede its predecessor atomically. Preserve previous versions and rate snapshots on historical transactions. Extra quantity or a new line requires a variation with PM approval followed by HO approval. Record exactly which variation increments a revision incorporates. Add only the remaining approved increments when calculating current entitlement.

### Claims, approvals and payment

Capture claimant, project, building, expense date or period, amount, GST if any, vendor/landlord, description and at least one photo/PDF reference with filename and local or uploaded path. Collect the following additional detail.

| Type | Additional data and posting rule |
| --- | --- |
| Site stay rent | Employee who stayed, place and inclusive stay dates. Post paid amount to Site overhead. |
| Allowance | Employee, allowance type (food, daily or conveyance), days and rate. Derive amount and post to Site overhead when paid. |
| Travel | Capture travel particulars and expense date. Use a configured head and allocation. Proposed default is Site overhead. |
| Tool rental | Tool, rental period, issue and project/building. Allocate paid cost to the project and retain the tool reference for drill-down. Proposed head is Site overhead. |
| Petty site purchase | Item particulars and allocation leaf where applicable. Default to Material and allow a permitted head override. |
| Other | Require a note and an explicit authorized allocation before payment. |

Build the route on submission. For a technician claimant include Supervisor first. Include Site Engineer next. Include PM for totals **above ₹10,000** or **any tool rental**. Finish with HO accounts. Skip a step when its assigned approver is the claimant. Identify an eligible assignee or flag an unresolved route before approval. Record every decision against a submission cycle. A returned claim requires a remark and returns to its claimant for editing and fresh routing. Rejection requires a remark and closes the claim. Allow claimant cancellation before payment on an open claim, recording a terminal cancellation event. Keep rejected claims closed.

Expose Draft, Submitted, Returned, Rejected, Approved, Payable and Paid. Keep the current review step separate from status. Final operational approval sets Approved. HO can review and return or reject, mark payable, and then mark paid with date and reference. Validate the completed route before payment. In one transaction record payment, post the actual by building, project and cost head, and append the audit event. Repeated clicks or retries must produce one payment and one posting per allocation.

### Actual costs and tools

- **Materials.** Post issue quantity × issue rate to the selected material leaf and building. Link any originating purchase so one expenditure enters comparison once.
- **Direct labor.** Record employee, date, building, project, leaf and hours. Snapshot the employee daily rate. Post hours × daily rate ÷ 8. At ₹800/day, six hours posts ₹600. Keep labor hours distinct from installed points or units.
- **Subcontract labor.** Assign the contractor and rate agreement to a package/leaf. Post certified subcontract quantity × agreed cost rate once. Match subsequent invoice and payment to that certification so settling the invoice does not post the cost again. Keep client billing rates independent of contractor rates.
- **Tools.** Track code, name, ownership, owner/vendor, daily or monthly rent, condition, holder and charged project. An issue records employee, project, building and start date. Return closes it with date and condition. Permit one open issue per tool. Damage/loss on an owned tool creates a note. For rented tools, display accrued rent, create or update one draft rental claim for the covered period, and post actual only at payment. A rental request by a Site Engineer can prefill the hire details. Prevent overlapping charged periods.

### Comparison and spending control

Aggregate from the same posted actuals, approved entitlement and issued bill lines for every screen. Support project, building, package, sub-head, optional BOQ line, cost head, level and date range. Keep Site overhead visible as a fourth reporting head and allow unallocated project/building overhead to roll up once. Sum amounts across mixed units. Display quantities only for compatible units and distinguish hours from completed work.

| Figure | Calculation |
| --- | --- |
| Quoted | Approved quotation quantity, rate and amount for the selected scope. Preserve historical revision context. |
| Committed ceiling | Quoted amount plus approved variation value outside that quotation. Apply each variation's own rate to its incremental quantity. |
| Actual | Posted material issues, labor attendance, subcontract certificates and paid claim allocations, including site expenses and tools. |
| Variance | Actual minus quoted. Percent is variance ÷ quoted × 100. Show percentage as unavailable where quoted is zero. |
| Billed | Sum issued bill lines once, including those subsequently collected. Drafts contribute zero. |
| Available to spend / bill | Committed ceiling minus actual / committed ceiling minus issued value, respectively, on a consistent tax basis. |
| Line status | Below 90% of quoted is Within limit. From 90% through 100% inclusive is Near limit. Above 100% is Overrun. For zero quoted and positive actual show Overrun and the amount. |

Show the overrun list against **quoted** and the available balance against **committed**. A ₹100 quoted line with a ₹20 approved variation and ₹105 actual shows ₹5 adverse variance, Overrun and ₹15 left to spend. For a new controllable cost, validate projected spend against the approved allocation under a database lock. Provide an explicit over-budget outcome and a route to request a variation. Preserve evidence of already-incurred expenses and distinguish recording a liability from authorizing additional spend. Resolve the overhead budget and incurred-cost policy below before enabling payment gates.

### Measurement, part billing and collection

1. Supervisor records field quantities or Site Engineer prepares them. Site Engineer submits measured quantities by project, building, period and leaf. PM certifies. Lock the entitlement during certification and reject a cumulative quantity above quoted quantity plus approved variation. Return the remaining quantity and offending line to the form.
2. HO drafts an RA bill for one project and period from PM-certified, unbilled quantities. Each line retains its node, certification allocation, previous certified quantity, this-period and cumulative quantities, approved rate source, current amount, GST and cumulative billed amount. Separate rate tranches when extra work carries a different rate. Keep previously certified quantities distinct from previously billed quantities.
3. At issue, recheck PM certification, remaining certified quantity, effective approved rate and current quantity/value ceilings. Lock allocations and the project bill counter. Issue and append the audit entry atomically. Number RA-0001 onward per project. Preserve issued snapshots for printing and historical comparison.
4. Show Draft measurement → Submitted → Certified → Bill drafted → Issued → Collected across the linked measurement and bill records. HO records receipt date, amount and reference. Reflect actual receipts in collection totals and mark Collected when net due is settled.
5. Derive leaf progress from certified physical quantity ÷ approved physical quantity including variations. Weight parent progress by approved value. If several cost heads price the same physical work, define a single measure and map its associated values before aggregating. Display unavailable progress when the denominator is zero.
6. The project control panel shows quoted contract value, approved variations, certified value, billed gross, retention held, net collected and cost to date. Show both margins explicitly as billed gross less cost and collected net less cost. Include previous bills, gross this bill, retention this bill, net payable and cumulative net on the bill itself.

**Proposed billing convention for stakeholder review.** Use pre-GST work values for entitlement, comparison and operating margin. Label billed gross on the control panel as gross work value before GST and retention. On the invoice show work value, GST, invoice gross including GST, retention and net due separately. Apply project retention (default 5%, editable) to pre-GST work. For 10 downlights at ₹1,150, work is ₹11,500, GST at 18% is ₹2,070, invoice gross is ₹13,570, retention is ₹575 and net payable is ₹12,995. Store the applied rates and rounded amounts per line. Show the receipt-based margin using net cash actually collected and label its basis. Obtain HO sign-off on the GST basis for each cost source and the two margin labels.

## 5. Database design and integrity

Use UUID primary keys internally, foreign keys for relationships and separate human-readable numbers. Use fixed-point decimals for quantities, hours, rates and percentages, and two decimal places for posted INR. Define rounding once and round posted line amounts before summing. Use business dates for work and payment, UTC timestamps for audit chronology and an explicit project reporting time zone.

| Tables | Principal fields, relationships and constraints |
| --- | --- |
| company, customer, location, building, project, project_building | Customer and scope on project, location on building, unique project/building pair, valid date range, status, depth of 2 or 3 and retention rate. Validate building membership on transactional records. |
| app_user, employee, project_assignment, contractor, contractor_assignment | Identity subject and one role per account, employee home location and daily rate, contractor trade and agreement, unique user/project and contractor/package assignments. |
| breakdown_node, quotation, quotation_line | Project, parent, level, display code, description and leaf unit. Unique project/revision and one active Approved revision per project. Carry leaf identity across revisions. Composite keys prevent cross-project parentage and allocation. |
| variation, variation_line, quotation_variation | Project, approval state, affected/new leaf, incremental quantity, rate, head and GST. Link incorporated variations to revisions to prevent double counting. |
| expense_claim, claim_line, claim_attachment, approval_step, claim_payment | Server EXP number, client UUID, claimant, building, dates, type-specific fields, allocation, tax and amount. Store attachment checksum, MIME type, size, filename and private object key. Steps carry cycle, ordinal, assigned reviewer, decision, remark and time. Unique payment per claim. |
| tool, tool_issue, daily_note | Tool terms and condition. Issue/return dates, holder, project/building, rate snapshot and rental claim link. Notes reference author, job, date and text. |
| material_issue, attendance, subcontract_certificate, contractor_invoice, contractor_payment | Source quantities, units, valuation rates, business dates and job dimensions. Invoice allocations reference certificates. Receipts/payments retain settlement references. |
| actual_posting | Project, building, leaf where allocable, cost head, quantity/unit, amount, effective date, source type, source line and posting purpose. Unique source allocation key. Correct posted costs with linked reversal and replacement entries. |
| measurement, measurement_line, bill, bill_line, bill_allocation, client_receipt | Measurement period, building, leaf, quantity, certification identity and date. Link issued quantities to certified lines through allocations. Store tax, retention, rate and quotation/variation snapshots. Unique project/bill number. |
| audit_event, request_deduplication, project_counter | Actor, timestamp, record, prior/new state, action, remark and request ID. Append approval, return, rejection, payment, certification and bill issue in the business transaction. Persist retry keys and results. |

Index assignments by user, queues by role/project/status, ledger rows by project/building/date/head/leaf and outstanding bill allocations by certification. Use migrations and repeatable demo seed scripts. Preserve historical records when retiring a master. Reject edits that orphan a cost, certificate or bill. Test migrations against an existing dataset and verify that ledger and bill totals reconcile before and after upgrade.

## 6. API contracts, security and operations

| API group under /v1 | Representative operations and safeguards |
| --- | --- |
| Session and assignments | Sign in, refresh, sign out, get current role and authorized projects. Refresh cached assignments after reconnect. |
| Projects and contracts | Manage masters and tree, submit/approve quotation revision, submit variation, record PM and HO decisions. Validate leaf/unit compatibility and expected record version. |
| Claims and files | Create/update draft, authorize upload, submit, list own claims or review queue, approve, return, reject, cancel, mark payable and pay. Calculate the route on the server. |
| Field records and contractors | Enter material issues, attendance and notes, issue/return tools, record subcontract certificates, invoices and payments. Validate scope and duplicate events. |
| Measurements and bills | Submit measurements, certify, list certified balance, draft, issue and record receipt. Enforce limits again inside the transaction. |
| Reports | Fetch comparison rows, project summary, source drill-down and print view using one authorized query model. Return applied filters, units, effective revision and reporting date. |

Use TLS, adaptive password hashing, short-lived access tokens, revocable refresh credentials and OS-protected credential storage. Restrict file uploads to allowed formats and sizes, validate contents and use short-lived authorized downloads. Keep secrets, attachments and credentials out of logs. For writes accept a request key and expected version. Return field errors for invalid data, an access error for insufficient scope and a conflict with refreshed balances for stale decisions. Log correlation IDs across client, API and database events.

Operate with encrypted database backups and object storage recovery, including a restore rehearsal that opens an attachment and reconciles an issued bill. Monitor sync backlog age, failed uploads, payment posting failures, conflicting certifications, API errors and backup age. Assign support owners for failed sync, account recovery and billing discrepancies. Roll out migrations compatibly with older mobile clients and exercise server rollback while queued claims remain on devices.

## 7. Seed data and acceptance fixtures

Seed Company A, CityCare Hospitals, Whitefield, Block A and Block B. Create the Active three-level **CityCare Block A electrification** project. Seed Internal electrification with Lighting, Power and Earthing, plus the Fire and ELV package. Add the following original approved quotation.

| Leaf | Cost head | Quantity × rate | Pre-GST amount |
| --- | --- | --- | ---: |
| Lighting, 20 W LED downlight supply and fix | Material | 400 Nos × ₹1,150 | ₹460,000 |
| Power, 4 sqmm Cu wire supply and lay | Material | 2,500 m × ₹85 | ₹212,500 |
| Earthing station | Subcontract labor | 12 Nos × ₹6,500 | ₹78,000 |
| Lighting installation | Direct labor | 400 points × ₹180 | ₹72,000 |
| **Original quotation** | | | **₹822,500** |

Seed technician, supervisor, siteengineer, pm, headoffice and contractor accounts at the siteledger.app domain, each with demo password `demo123` in the demo environment. Assign the five employees to the project, set the technician rate to ₹800/day and restrict MNO Cabling to the earthing subcontract. Seed an owned megger, rented scaffolding currently issued at ₹500/day, one Submitted stay-rent claim, one Paid allowance with its ledger entry and one rental pending PM approval. Include material issues, two attendance days, a certified partial downlight measurement with RA-0001 issued and a draft wire measurement within ceiling.

Choose deterministic fixture quantities. For example, use the 10-downlight bill above and two eight-hour technician days costing ₹1,600. Include an explicit overrun fixture visible to the reviewer, such as a material line whose posted actual exceeds its original quote but is covered by a separately approved variation. Seed its approval trail. Include a second, two-level project in tests to verify sub-head billing and access isolation.

## 8. Implementation stages in delivery order

Each stage ends with evidence that the next stage can use. Assign the named responsibilities to available team members during kickoff. Estimate calendar dates after confirming team capacity, test hardware and accounting decisions.

| Stage | Lead and dependencies | Work and exit evidence |
| --- | --- | --- |
| 1. Confirm commercial examples | Product owner, HO accounts, PM and field lead | Agree the policy decisions below. Walk one claim, one rental and one RA bill on paper. Save expected numbers and the permission matrix as acceptance fixtures. |
| 2. Establish the platform | Backend, Flutter and release leads, after 1 | Create environments, migrations, API contract, identity, private file storage and build pipelines. Sign in to the same test account from Android and Windows. Demonstrate that unauthorized project access fails. |
| 3. Build project and quotation masters | Backend and Windows frontend, after 2 | Deliver masters, project assignments, both breakdown depths, quotations and variations. Approve a revision and prove the old version remains readable. Load the CityCare baseline. |
| 4. Ship the claim-to-cost slice | Flutter field/office and backend leads, after 3 | Deliver offline capture, attachments, sync, routing, audit, payment and initial ledger view. Save an allowance offline, reconnect, approve in sequence and pay once. Reconcile the Site overhead increase on both devices. |
| 5. Complete field cost capture | Field and backend leads, after 4 | Add daily notes, material issues, attendance, subcontract costs/invoices, rental requests and tool issue/return. Reconcile all four heads and check duplicate source handling. |
| 6. Deliver comparison and spend control | Reporting and backend leads, after 5 | Implement filters, limits, rollups, overrun list, Android cards and Windows print layout. Match totals to source postings and approved variations, including overhead and boundaries at 90% and 100%. |
| 7. Certify work and issue part bills | PM, HO and engineering, after 6 | Deliver measurement, certification, RA issue, retention, receipts and project progress. Block excess quantity, approve a variation, then certify. Issue RA-0002 once and reconcile cumulative work and receipts. |
| 8. Complete dashboards and system testing | QA and both client leads, after 7 | Finish role dashboards, contractor visibility and full demo seed. Run the acceptance suite below on both builds, including narrow/wide layouts and loss of connectivity. Record results by device and build. |
| 9. Package, pilot and release | Release owner, HO and a pilot site, after 8 | Deliver signed packages, service deployment, migration and recovery instructions, README and sample walkthrough. Run one pilot claim and one billing period against manual totals. Release after field and HO owners reconcile them. |

## 9. Verification and handover

| Test | Expected evidence |
| --- | --- |
| Approval boundaries | A technician ordinary claim at ₹10,000 routes Supervisor → Site Engineer → HO. At ₹10,000.01 it also goes to PM. A ₹500 tool rental goes to PM. Self-steps skip. A missing remark blocks return/reject. Resubmission preserves prior cycles. |
| Offline payment path | Technician saves allowance in airplane mode, restarts, reconnects and submits once. Supervisor and Site Engineer approve. HO marks payable then paid. Payment date/reference and one Site overhead posting appear on both clients. Paid claims resist cancellation. |
| Comparison | Fixtures prove actual minus quoted, percent, all head totals and both balances. Cover zero quote, mixed units, building filters, date cutoffs and threshold boundaries. Windows print agrees with Android cards. |
| Billing ceiling | With 400 quoted downlights and 10 already certified, 391 additional units fail. After PM and HO approve 5 extra units, 391 pass. Draft or singly approved variations leave the prior limit in force. |
| Concurrent decisions | Two submissions competing for the same remaining quantity cannot both consume it. Retry payment, certification and RA issue after acknowledgment loss. Verify unique postings, unique bill numbers and preserved audit history. |
| Bills and settlement | An uncertified wire line blocks issue. Partial billing of certified work leaves the correct unbilled balance. Under the proposed billing convention the 10-downlight example yields ₹12,995 net. Collect it and verify both margins and cumulative receipts. |
| Security and history | Unassigned employee and unrelated contractor cannot read records, files or exports. HO can see all projects. A superseded quotation remains readable. A later revision leaves a previously issued bill reproducible. |
| Recovery and platform release | Restore a backup and reconcile postings, receipts and attachments. Launch on Android and Windows. If either cannot launch, record the exact platform and run shared tests for routing, ceiling, retention and variance. Track outstanding platform verification. |

The README must describe stack, prerequisites, backend start-up, migrations, environment settings, seed/reset procedure for demo, Android and Windows build/run steps, demo users, offline sync, approval rules and billing rules. Include a reproducible seed walkthrough from allowance to payment and from draft wire measurement to certification and the next RA bill. Record tested builds, platform results, known limitations, backup owner and support contact.

## 10. Business decisions to record in stage 1

| Decision and owner | Proposed starting point and impact |
| --- | --- |
| Overhead budget and incurred spend — HO and PM | The original quote has three cost heads while rent and allowances post to a fourth. Establish an approved overhead allocation within the project ceiling so a valid payment can proceed. Define who resolves over-budget liabilities and how imported overruns remain visible. |
| Building allocations and reporting periods — HO | Allocate quoted quantities/value to buildings when several share a BOQ line. Validate that building shares sum to the project line. Use period activity for movements and opening plus movements for as-of balances. State both dates in exports. |
| GST, retention and rounding — HO | Sign off the worked bill, recoverable input GST treatment, rounding and whether retention varies by line. Snapshot the project's retention at issue. |
| Routing and expense composition — operations | Use total payable including claimed GST for the ₹10,000 test. Use one claim type per claim with multiple particulars. Agree delegated approvers, HO-originated claims and cancellation display so self-approval cannot authorize payment. |
| Progress, variations and revisions — PM and HO | Agree how physical measures map to separately priced supply and labor, and how to reconcile a new revision against prior variation quantities, certificates and issued bills. Block revisions that strand existing allocations until resolved. |
| Rental periods and proration — site lead and HO | Agree inclusive hire dates, how monthly rentals prorate and when a long-running hire creates a claim. Preserve billed-through dates so return or resync cannot recreate a charged period. |
| Deployment and support — release owner | Confirm hosting, Windows distribution, Android device support, attachment limits, retention period, recovery objectives and production account provisioning before pilot. |
