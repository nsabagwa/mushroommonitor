// scripts/check-alerts.js
//
// Run on a schedule by .github/workflows/check-alerts.yml (free GitHub
// Actions cron — no Firebase Blaze plan, no Cloud Functions required).
//
// For every farm stored in Firebase Realtime Database it:
//   1. fetches the latest ThingSpeak reading
//   2. compares it to that farm's thresholds for its current growth stage
//   3. emails the owner via Gmail SMTP if anything is out of range
//   4. writes back an alertState node (for cooldown / recovery tracking)
//
// Data shape in Realtime Database, written by the Flutter app (see
// lib/data/repositories/alert_sync_repository.dart):
//
// farms/{farmId}
//   ownerUid: string
//   ownerEmail: string
//   name: string
//   thingSpeakChannelId: string
//   thingSpeakReadApiKey: string
//   thingSpeakFieldMap: { temperature, humidity, co2, light }
//   currentStage: "incubation" | "pinning" | "fruiting"
//   alertsEnabled: bool
//   thresholds: {
//     incubation: { tempMin, tempMax, rhMin, co2Max },
//     pinning:    { tempMin, tempMax, rhMin, co2Max },
//     fruiting:   { tempMin, tempMax, rhMin, co2Max }
//   }
//   alertState: { outOfRange: bool, lastAlertAt: number (ms epoch) }

const admin = require("firebase-admin");
const nodemailer = require("nodemailer");
const fetch = require("node-fetch");

const ALERT_COOLDOWN_MS = 2 * 60 * 60 * 1000; // 2 hours

function requireEnv(name) {
  const v = process.env[name];
  if (!v) {
    console.error(`Missing required env var: ${name}`);
    process.exit(1);
  }
  return v;
}

const FIREBASE_DATABASE_URL = requireEnv("FIREBASE_DATABASE_URL");
const FIREBASE_SERVICE_ACCOUNT = requireEnv("FIREBASE_SERVICE_ACCOUNT_JSON");
const GMAIL_USER = requireEnv("GMAIL_USER");
const GMAIL_APP_PASSWORD = requireEnv("GMAIL_APP_PASSWORD");

admin.initializeApp({
  credential: admin.credential.cert(JSON.parse(FIREBASE_SERVICE_ACCOUNT)),
  databaseURL: FIREBASE_DATABASE_URL,
});
const db = admin.database();

const transport = nodemailer.createTransport({
  service: "gmail",
  auth: { user: GMAIL_USER, pass: GMAIL_APP_PASSWORD },
});

async function fetchLatestThingSpeakReading(channelId, readApiKey, fieldMap) {
  const url = `https://api.thingspeak.com/channels/${channelId}/feeds/last.json?api_key=${readApiKey}`;
  const res = await fetch(url);
  if (!res.ok) throw new Error(`ThingSpeak request failed: ${res.status}`);
  const feed = await res.json();
  if (!feed || !feed.created_at) return null;

  const fields = fieldMap || {
    temperature: "field1",
    humidity: "field2",
    co2: "field3",
    light: "field4",
  };

  const num = (key) => {
    const raw = feed[fields[key]];
    return raw === undefined || raw === null ? null : parseFloat(raw);
  };

  return {
    temperatureC: num("temperature"),
    relativeHumidity: num("humidity"),
    co2Ppm: num("co2"),
    timestamp: feed.created_at,
  };
}

function checkViolations(reading, thresholds) {
  if (!thresholds) return [];
  const violations = [];

  if (reading.temperatureC !== null) {
    if (reading.temperatureC < thresholds.tempMin) {
      violations.push(
        `Temperature ${reading.temperatureC.toFixed(1)}\u00b0C is below the minimum (${thresholds.tempMin}\u00b0C)`
      );
    } else if (reading.temperatureC > thresholds.tempMax) {
      violations.push(
        `Temperature ${reading.temperatureC.toFixed(1)}\u00b0C is above the maximum (${thresholds.tempMax}\u00b0C)`
      );
    }
  }

  if (reading.relativeHumidity !== null && reading.relativeHumidity < thresholds.rhMin) {
    violations.push(
      `Humidity ${reading.relativeHumidity.toFixed(0)}% is below the minimum (${thresholds.rhMin}%)`
    );
  }

  if (reading.co2Ppm !== null && reading.co2Ppm > thresholds.co2Max) {
    violations.push(
      `CO\u2082 ${Math.round(reading.co2Ppm)} ppm is above the maximum (${thresholds.co2Max} ppm)`
    );
  }

  return violations;
}

async function sendAlertEmail(toEmail, farmName, violations, reading) {
  const lines = violations.map((v) => `\u2022 ${v}`).join("\n");
  await transport.sendMail({
    from: `MushPi Hub Alerts <${GMAIL_USER}>`,
    to: toEmail,
    subject: `\u26a0\ufe0f Out-of-range alert: ${farmName}`,
    text:
      `Your farm "${farmName}" has a reading out of range as of ${reading.timestamp}:\n\n` +
      `${lines}\n\nOpen the MushPi Hub app to check on it.`,
    html:
      `<p>Your farm <strong>${farmName}</strong> has a reading out of range ` +
      `as of ${reading.timestamp}:</p>` +
      `<ul>${violations.map((v) => `<li>${v}</li>`).join("")}</ul>` +
      `<p>Open the MushPi Hub app to check on it.</p>`,
  });
}

async function main() {
  const snapshot = await db.ref("farms").once("value");
  const farms = snapshot.val() || {};
  const results = [];

  for (const [farmId, farm] of Object.entries(farms)) {
    if (farm.alertsEnabled === false) continue;
    if (!farm.thingSpeakChannelId || !farm.thingSpeakReadApiKey) continue;

    try {
      const reading = await fetchLatestThingSpeakReading(
        farm.thingSpeakChannelId,
        farm.thingSpeakReadApiKey,
        farm.thingSpeakFieldMap
      );
      if (!reading) continue;

      const stage = farm.currentStage || "fruiting";
      const thresholds = farm.thresholds && farm.thresholds[stage];
      const violations = checkViolations(reading, thresholds);

      const alertState = farm.alertState || { outOfRange: false, lastAlertAt: 0 };
      const now = Date.now();

      if (violations.length > 0) {
        const shouldSend =
          !alertState.outOfRange || now - (alertState.lastAlertAt || 0) > ALERT_COOLDOWN_MS;

        if (shouldSend) {
          const toEmail = farm.ownerEmail;
          if (toEmail) {
            await sendAlertEmail(toEmail, farm.name || farmId, violations, reading);
            results.push({ farmId, emailed: toEmail, violations });
          } else {
            results.push({ farmId, skipped: "no ownerEmail" });
          }
        }

        await db.ref(`farms/${farmId}/alertState`).set({
          outOfRange: true,
          lastAlertAt: shouldSend ? now : alertState.lastAlertAt || now,
        });
      } else if (alertState.outOfRange) {
        await db.ref(`farms/${farmId}/alertState`).set({
          outOfRange: false,
          lastAlertAt: alertState.lastAlertAt || 0,
        });
        results.push({ farmId, recovered: true });
      }
    } catch (err) {
      results.push({ farmId, error: err.message });
    }
  }

  console.log("check-alerts results:", JSON.stringify(results, null, 2));
}

main()
  .then(() => process.exit(0))
  .catch((err) => {
    console.error(err);
    process.exit(1);
  });
