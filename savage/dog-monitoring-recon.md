# Dog Monitoring System — Recon Report
**Agent: Savage | Date: 2026-05-19 | Scope: Condo-scale, single dog, 8-10hr solo stretches**

---

## TL;DR

You have three honest paths forward:
1. **Cheap + effective**: Wyze Cam v4 ($36) + barking audio alerts = 80% of what you need for <$50/yr.
2. **Premium camera + treat play**: Furbo 360 ($184) or Petcube Play 2 (~$150) + two-way audio + treat launcher.
3. **DIY interactive rover**: Pi 5 + USB camera + motor/chassis + treat dispenser (~$300–400 parts) — real prototype, 6–8 weeks to working unit.

Commercial floor robots (Tombot Jennie, Loona, AIBO) are **not** for dog monitoring; they're lap companions or toys. Skip them. The "floor robot" angle only makes sense DIY or abandoned.

---

## 1. What "Dog Monitoring" Actually Means (Real Options, 2026)

### A. Stationary Cameras (Proven, Shipping Today)

| Product | Price | Key Feature | Monthly | Verdict |
|---------|-------|-------------|---------|---------|
| **Wyze Cam v4** | $36 | 1080p, person/pet detection, night vision | $1.99 (Cam Plus) | Best bang-for-buck. Audio alerts no cost. |
| **Furbo 360** | $184 | Treat launcher, bark detection, 160° FOV | $6.99 (Dog Nanny) | Best for interaction. Real bark sensor. |
| **Petcube Play 2** | ~$150 | Built-in laser toy, 180° FOV, 4x zoom | <$5 (Petcube Care) | Mid-ground. Laser keeps them engaged. |
| **Eufy Indoor Cam 2K** | ~$60 | AI tracking, night vision, local storage option | Optional | Good budget alternative. |

**Real talk**: 90% of solo dogs sleep through the day. A $36 Wyze cam with sound alerts catches the 10% (barking, drinking water, zoomies). Treat launcher is nice-to-have, not need-to-have.

### B. Behavioral Detection (Separation Anxiety Angle)

- **Smart bark collars** (Dogtra Smart NOBARK, KJKZO AI, ~$80–150): Triple-sensor detection filters false positives. Track barking patterns via app.
- **IoT collar monitoring**: Patent-filed tech uses SVM to detect whining + posture + motion to flag separation anxiety states.
- **Furbo's barking sensor**: Detects bark vs. environmental noise. Sends you a clip within 30 seconds.

**Reality check**: These detect the symptom, not solve it. Useful for logging *when* he stresses, not *why*.

### C. Drinking/Eating (Lower Priority)

- Water level sensors exist (e.g., Enabot water fountain cameras) but don't fit a typical dog-alone scenario.
- Food dispensers (auto-feeders + camera) run $100–300 but assume you're away during scheduled meals. Useful only if you leave him 12+ hours.

---

## 2. The "Floor Robot" Question — Hard Truth

### Commercial Floor Robots for Dogs (2026)
- **Tombot Jennie**: $1,000–1,500. *Design intent: elderly dementia patients.* Static on lap. NOT for floor roaming. Safety first = no trip hazards.
- **Loona Petbot**: $499–600. AI chat, games, laser. *Sits on floor, mostly stationary.* Great for kids bored in summer. Not dog-monitoring.
- **Sony AIBO ERS-1000**: $2,899+. Robot dog that walks around. Dog may chase it or ignore it. Expensive glorified toy for *your* entertainment, not monitoring.
- **Boston Dynamics Spot**: $74,500. Inspection quadruped. Not a dog product.

**Bottom line**: Every commercial "robot dog" is either a companion toy for humans or a stationary lap pet. None are designed to monitor your dog or deliver treats autonomously in a home setting.

### DIY Floor Robot (Actual Feasibility)

**The real option** if you want interactive floor coverage:

**Parts Cost Breakdown:**
- Raspberry Pi 5 (8GB): $80
- USB camera (HD, 90° FOV): $20–30
- Motor kit (4WD chassis): $80–150
- Servo motor (treat dispenser): $15–25
- Power bank + wiring: $30
- 3D-printed chassis / enclosure: ~$0 (reuse existing parts) or $20–40 (print locally)
- **Total: $225–325**

**Reality on effort:**
- Skeleton working rover (move + stream): 3–4 weeks.
- Treat delivery (reliable servo + hopper): +2 weeks.
- Dog interaction (detect motion, respond, log): +2–3 weeks.
- **6–8 weeks to "minimal viable prototype."**

**This is not a weekend project.** You're building:
1. Motor control code (GPIO, PWM).
2. Camera feed to local Tailscale endpoint.
3. State machine (idle → chase → dispense → log).
4. Persistence for movement heatmaps / interaction logs.

**Why DIY might fit your workflow:**
- You already have Pi infrastructure + Tailscale mesh + Pixel dashboards.
- Data lives on your network, not Furbo's cloud.
- You can modify behavior (treat interval, audio response, motion detection).
- You learn robotics while solving a real problem.

**Why DIY is risky:**
- Dog could catch motor cord, chew chassis, cause chaos.
- Rover failures leave him with zero monitoring (unlike a static camera fallback).
- You're 8 weeks in before you know if he even cares.

---

## 3. HARK Infra Angle: What Integrates Cleanly

### If You Go Camera-Only

**Wyze + Tailscale Integration (Real):**
- Wyze V3 cameras can run wz_mini_hacks firmware, support Tailscale directly.
- Stream via local RTSP, drop into your existing Pi-based dashboard.
- No Wyze cloud required.
- Cost: $36 camera + your infra = done.

**Dashboard Entry Points:**
- Motion events → ntfy.sh push ("dog detected moving").
- Bark events → Discord webhook (fit into incident-log pattern).
- Playback via local ffmpeg + video-serving endpoint on Pi.

### If You Go DIY Rover + Camera

**Natural dashboard layer:**
- Rover publishes: `{position: [x, y], battery: %, treats_dispensed: N, motion_detected: true/false, timestamp}` to local MQTT.
- Same pattern as your greenhouse sensors (Fluxuum). Dead simple to wire into Facility Tracker or new CannaMax-style pet dashboard.
- Heatmap of where dog spent time.
- Treat dispense log (did he eat it? when?).
- Battery health alerts.

**This is elegant because:**
- You already know how to build the sensor→dashboard pipeline.
- Data schema is trivial compared to Infinium env readings.
- No cloud dependency.
- Pixel 10 tap-in can show rover state live.

---

## 4. Trade-Off Matrix

| Path | Hardware Cost | Setup Time | Cloud Dependency | Interactivity | Dog Learning Curve | Best For |
|------|--------------|-----------|-----------------|---------------|------------------|----------|
| **Wyze Cam v4** | $36 | 30 min | Yes (optional Cam Plus) | Audio/alerts only | N/A | Peace of mind, budget |
| **Furbo 360** | $184 | 1 hour | Yes (required Dog Nanny for bark) | Treats + audio | 1–2 weeks | Full monitoring + engagement |
| **DIY Rover** | $225–325 | 6–8 weeks | None | Treats + movement | 2–4 weeks | Learning + long-term hobby |

### Budget Breakdown for Each

**Conservative Setup (Wyze Only):**
- Camera: $36
- Cam Plus (12 mo): $24
- **Annual: $60**

**Full Experience (Furbo):**
- Camera: $184
- Dog Nanny (12 mo): $84
- **Annual: $268**

**DIY Rover (One-Time + Electricity):**
- Initial parts: $300
- Pi power (~2W average, 8hr/day): <$1/yr
- Replacement parts (servo, motor bearings): ~$20–30/yr
- **Year 1: $300 | Year 2+: $25–30**

---

## 5. Honest Assessment: Is This Worth It?

### Red Flags
1. **Dog probably sleeps 80% of the time you're gone.** A static camera catching "he's alive" is 95% of utility.
2. **Floor robot = maintenance + failure modes.** Servo jams. Battery dies. Dog disinters the dispenser.
3. **Separation anxiety is behavioral, not tech-solvable.** Monitoring doesn't fix it. Training, exercise, or vet pharma does.
4. **Condo constraints.** Floor space limited. Neighbors below. Rover noise/activity might be annoying.

### Green Lights
1. **You have Tailscale + Pi + existing dashboard infra.** No external dependencies. Data is yours.
2. **You build high-quality systems for precision domains (cannabis).** Dog monitoring will be overbuilt and reliable.
3. **The "learning project" angle is real.** Robotics + sensor integration = skills that transfer to HARK controller roadmap.
4. **Curiosity is valid.** If the question keeps coming back, it's worth one prototype cycle.

---

## 3 Recommendations (Priority Order)

### 1. **Start with Wyze Cam v4 + offline streaming (2–3 days)**
   - Buy camera. Flash wz_mini_hacks firmware. Get RTSP stream on Tailscale.
   - Wire bark detection into ntfy.sh or Discord webhook.
   - Cost: $36. Risk: zero (return if useless).
   - **Decision point**: If bark alerts feel redundant or dog doesn't care about audio, pause here.

### 2. **If camera alone feels incomplete, rent Furbo for a month (DIY or borrow)**
   - Borrow a Furbo 360 from a friend or rent via Peerby/Neighbor.
   - Run it parallel to Wyze for 3–4 weeks.
   - Does dog actually engage with treats? Does bark detection add real signal?
   - **Decision point**: If yes, buy Furbo. If no, skip to #3 or abandon.

### 3. **DIY rover: build in a worktree, 4-week sprint (if you're hooked)**
   - Scope: Tele-operated rover (remote control via Pi Tailscale), USB camera feed, single servo for treat pusher.
   - Metrics: Can you drive it, stream video, dispense a treat, and log the event?
   - **Decision point**: Once working, run for 2 weeks live. If dog learns to seek it out, iterate on autonomy. If neglected, bench it and keep Wyze.

---

## Sources
- [Best Pet Cameras of 2026 | SafeWise](https://www.safewise.com/blog/8-pet-cameras-every-pet-owner-should-know-about/)
- [Best Pet Cameras in 2026: Top 5 Picks From $36 to $210 | Smart Pet Gear Lab](https://smartpetgearlab.com/posts/best-pet-cameras-2026/)
- [Furbo 360° Dog Camera](https://furbo.com/us/products/furbo-360-dog-camera)
- [Tombot's 'Jennie' puppy at CES 2026 | WTOP News](https://wtop.com/tech/2026/01/tombots-jennie-puppy-steals-hearts-at-ces-2026-with-real-world-demos-of-robotic-companionship/)
- [How Much Does a Robot Dog Really Cost in 2026? | Loona Blog](https://keyirobot.com/blogs/buying-guide/how-much-does-a-robot-dog-really-cost-in-2025)
- [DIY Raspberry Pi automatic dog or cat feeder | Viam](https://www.viam.com/post/smart-pet-feeder)
- [Set up a dog camera with Tailscale, Raspberry Pi, and Motion | Tailscale Docs](https://tailscale.com/kb/1076/dogcam)
- [Building a Remote CCTV System with TailScale | Medium](https://medium.com/@sampsa.riikonen/building-a-remote-cctv-system-with-tailscale-7532e8744e3f)
- [Dogtra Smart NOBARK](https://dogtra.com/products/dogtra-smart-nobark)

---

**End Report**

The floor robot angle is real but only as a DIY learning project. Commercial floor robots are companions, not monitors. Your best bet: start with a $36 camera, run it offline via Tailscale, hook bark detection into your existing alert stack. If that feels hollow after a month, *then* prototype a rover and learn robotics while solving a real problem.
