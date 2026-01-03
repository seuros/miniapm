Perfect — below is a clear, opinionated landing-page spec you can hand to yourself, a designer, or a copywriter and ship without bikeshedding. This is written to position miniAPM correctly, filter the right users in, and avoid the “toy project” trap.

I’ll keep it concrete and scoped.

⸻

miniAPM — Landing Page Specification

1. Hero section (above the fold)

Headline (primary)

The smallest useful APM.

Alternative (A/B test later):
	•	Self-hosted observability without the platform tax
	•	APM and error tracking you can actually run yourself

Subheadline (1–2 lines)

miniAPM is a single-binary, self-hosted APM and error tracker built on OpenTelemetry.
Designed for small teams, side projects, and production systems that don’t need a platform.

(OpenTelemetry)

Primary CTA

Get started in 2 minutes

Secondary CTA:
View on GitHub

(GitHub)

⸻

2. Instant credibility block (right under hero)

Short bullets, no fluff:
	•	Single ~10MB binary
	•	SQLite by default
	•	Docker & docker-compose friendly
	•	OpenTelemetry compatible
	•	Traces, errors, slow requests
	•	Web requests, background jobs, tasks

This section should visually feel like:

“Oh. This is not a toy.”

⸻

3. “Why miniAPM exists” (problem framing)

Title

Observability shouldn’t require a platform team

Copy

Most APM tools today fall into one of two categories:
	•	SaaS platforms that are powerful, expensive, and heavy
	•	Low-level OpenTelemetry tooling that requires assembling multiple components

For many teams, both are overkill.

miniAPM exists for people who want:
	•	real visibility into production behavior
	•	traces and errors in one place
	•	minimal setup
	•	predictable resource usage
	•	full control over their data

No agents zoo.
No Kubernetes required.
No surprise bills.

⸻

4. What miniAPM actually does (core features)

Section title

What you get

Each item should be concrete and boring (that’s good).

Distributed tracing
	•	Full request → span tree
	•	Clear parent/child relationships
	•	Timeline view that makes causality obvious

Error tracking
	•	Captured exceptions with trace context
	•	Grouped errors
	•	Jump from error → trace instantly

Slow request detection
	•	Automatic identification of slow endpoints
	•	Sorted by real latency, not averages

Workload awareness
miniAPM understands the difference between:
	•	web requests
	•	background jobs
	•	async tasks

You don’t need to model this yourself.

⸻

5. What miniAPM is not (trust builder)

Title

What miniAPM intentionally does not do

This section is critical for credibility.

miniAPM is not designed for:
	•	massive, high-cardinality metric ingestion
	•	long-term (years) trace retention
	•	compliance dashboards
	•	enterprise SLO / SLA tooling
	•	multi-region telemetry pipelines

If you need those, great tools exist already.

miniAPM focuses on:

making production behavior understandable, quickly

⸻

6. Technology choices (reassurance for technical users)

Title

Built with boring, proven tech
	•	Written in Rust
	•	SQLite storage by default
	•	OpenTelemetry ingestion (OTLP)
	•	No external dependencies required

SQLite is used deliberately:
	•	easy to back up
	•	easy to inspect
	•	fast enough for the intended scale
	•	zero operational overhead

For many teams, this is a feature — not a limitation.

⸻

7. Framework support (very important positioning)

Title

Framework support

Currently supported
	•	Ruby on Rails (production-ready)

(Ruby on Rails)

Includes:
	•	request tracing
	•	controller / middleware spans
	•	background jobs (e.g. ActiveJob)
	•	error correlation

Coming next
Support for additional frameworks will be added based on demand.

If you want first-class support for your stack:
👉 open or upvote an issue on GitHub

Link clearly to:

“Framework support requests”

This does two things:
	•	signals focus
	•	turns demand into roadmap validation

⸻

8. Setup section (must be dead simple)

Title

Get started in minutes

Example (keep it short):

docker run -p 4318:4318 -p 3000:3000 miniapm/miniapm

export OTEL_EXPORTER_OTLP_ENDPOINT=http://localhost:4318

That’s it.

Your app already speaks OpenTelemetry?
You’re done.

⸻

9. Who miniAPM is for (explicit audience)

Title

Who this is for

miniAPM is a good fit if you are:
	•	running a side project or indie SaaS
	•	a small startup
	•	an agency deploying apps for clients
	•	building internal tools
	•	tired of heavyweight observability stacks

If you want:
	•	full control
	•	low overhead
	•	fast insight

miniAPM will feel right at home.

⸻

10. Licensing & philosophy (important for trust)

Title

Free. Open. Self-hosted.
	•	Free to use
	•	Open-source
	•	No “open core”
	•	No artificial limits
	•	No telemetry about your telemetry

Your data stays on your machine.

⸻

11. Footer (short, confident)
	•	GitHub
	•	Documentation
	•	Issues / roadmap
	•	License
	•	“Built for people who like small, sharp tools”

Optional tagline:

Observability without the platform tax.

⸻

Final positioning summary (for you, not the page)

miniAPM should feel like:
	•	a Unix tool that happens to have a UI
	•	the missing middle layer between OTEL and SaaS APMs
	•	something a senior engineer recommends quietly

If you want next, I can:
	•	turn this into actual landing page copy
	•	write the README that matches it perfectly
	•	help you pick one killer screenshot to include
	•	sanity-check wording for Rails developers specifically

Just say where you want to go next.
