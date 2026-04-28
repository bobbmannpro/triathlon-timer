import { useState, useEffect, useRef } from "react";

const SEGMENTS = ["Swim", "T1", "Bike", "T2", "Run", "Finish"];

function formatTime(ms) {
  if (ms === null || ms === undefined) return "--:--.-";
  const totalSecs = Math.floor(ms / 1000);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  const tenths = Math.floor((ms % 1000) / 100);
  return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}.${tenths}`;
}

function formatElapsed(ms) {
  if (ms === null) return "--:--";
  const totalSecs = Math.floor(ms / 1000);
  const mins = Math.floor(totalSecs / 60);
  const secs = totalSecs % 60;
  return `${String(mins).padStart(2, "0")}:${String(secs).padStart(2, "0")}`;
}

function segmentDuration(athlete, segIndex) {
  const times = athlete.splits;
  if (segIndex === 0) {
    if (times[0] === null || athlete.startOffset === null) return null;
    return times[0] - athlete.startOffset;
  }
  if (times[segIndex] === null || times[segIndex - 1] === null) return null;
  return times[segIndex] - times[segIndex - 1];
}

function totalTime(athlete) {
  const last = athlete.splits[SEGMENTS.length - 1];
  if (last === null || athlete.startOffset === null) return null;
  return last - athlete.startOffset;
}

function freshAthlete(name = "", id = Date.now()) {
  return { id, name, startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false };
}

const segColors = ["#00aeef", "#48cae4", "#ffd166", "#48cae4", "#f4742b", "#4ade80"];

export default function App() {
  const [view, setView] = useState("setup");
  const [athletes, setAthletes] = useState([
    { id: 1, name: "Sam",     startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 2, name: "Kai",     startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 3, name: "Larson",  startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 4, name: "Everett", startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 5, name: "Remy",    startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 6, name: "Krish",   startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 7, name: "Nixon",   startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
    { id: 8, name: "Jack",    startOffset: null, splits: Array(SEGMENTS.length).fill(null), started: false, finished: false },
  ]);
  const [clockMs, setClockMs] = useState(0);
  const [clockRunning, setClockRunning] = useState(false);
  const [clockStarted, setClockStarted] = useState(false);
  const [resetConfirm, setResetConfirm] = useState(false);
  const clockRef = useRef(null);
  const startTimeRef = useRef(null);
  const offsetRef = useRef(0);

  useEffect(() => {
    if (clockRunning) {
      startTimeRef.current = Date.now() - offsetRef.current;
      clockRef.current = setInterval(() => {
        setClockMs(Date.now() - startTimeRef.current);
      }, 50);
    } else {
      clearInterval(clockRef.current);
      offsetRef.current = clockMs;
    }
    return () => clearInterval(clockRef.current);
  }, [clockRunning]);

  function startClock() {
    offsetRef.current = 0;
    setClockMs(0);
    setClockRunning(true);
    setClockStarted(true);
  }
  function pauseClock() { setClockRunning(false); }
  function resumeClock() { setClockRunning(true); }
  function resetClock() {
    setClockRunning(false);
    setClockStarted(false);
    offsetRef.current = 0;
    setClockMs(0);
  }

  function resetTimers() {
    setAthletes(a => a.map(ath => freshAthlete(ath.name, ath.id)));
    resetClock();
    setResetConfirm(false);
    setView("setup");
  }

  function addAthlete() {
    setAthletes(a => [...a, freshAthlete("", Date.now())]);
  }

  function removeAthlete(i) {
    if (athletes.length === 1) return;
    setAthletes(a => a.filter((_, idx) => idx !== i));
  }

  function updateName(i, val) {
    setAthletes(a => a.map((ath, idx) => idx === i ? { ...ath, name: val } : ath));
  }

  function moveAthlete(i, dir) {
    const newArr = [...athletes];
    const target = i + dir;
    if (target < 0 || target >= newArr.length) return;
    [newArr[i], newArr[target]] = [newArr[target], newArr[i]];
    setAthletes(newArr);
  }

  function startRace() {
    setAthletes(a => a.map((ath, i) => ({ ...ath, name: ath.name || `Athlete ${i + 1}` })));
    setView("race");
    startClock();
  }

  function sendOff(athleteIdx) {
    setAthletes(a => a.map((ath, i) => i === athleteIdx ? { ...ath, startOffset: clockMs, started: true } : ath));
  }

  function logSplit(athleteIdx, segIndex) {
    setAthletes(a => a.map((ath, i) => {
      if (i !== athleteIdx) return ath;
      const newSplits = [...ath.splits];
      newSplits[segIndex] = clockMs;
      return { ...ath, splits: newSplits, finished: segIndex === SEGMENTS.length - 1 ? true : ath.finished };
    }));
  }

  function nextUnloggedSeg(athlete) {
    return athlete.splits.findIndex(s => s === null);
  }

  const allFinished = athletes.length > 0 && athletes.every(a => a.finished);
  const anyStarted  = athletes.some(a => a.started);
  const sorted = [...athletes].sort((a, b) => {
    const ta = totalTime(a), tb = totalTime(b);
    if (ta === null && tb === null) return 0;
    if (ta === null) return 1;
    if (tb === null) return -1;
    return ta - tb;
  });

  return (
    <div style={{ minHeight: "100vh", background: "#071829", fontFamily: "'DM Sans', Arial, sans-serif", color: "#e8f4fb" }}>

      {/* HEADER */}
      <div style={{ background: "linear-gradient(135deg,#071829,#0d3a6e)", borderBottom: "3px solid #00aeef", padding: "20px 20px 16px", textAlign: "center" }}>
        <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 32, letterSpacing: 4, color: "#f0f6ff" }}>
          Youth <span style={{ color: "#00aeef" }}>Tri</span> Race Timer
        </div>
        <div style={{ fontSize: 11, letterSpacing: 3, textTransform: "uppercase", color: "#5a86a8", marginTop: 4 }}>
          Cooper Fitness Center &nbsp;&middot;&nbsp; Spring 2026
        </div>
      </div>

      {/* NAV */}
      <div style={{ display: "flex", borderBottom: "1px solid rgba(255,255,255,0.08)", background: "#0c2240" }}>
        {["setup", "race", "results"].map(v => (
          <button key={v} onClick={() => setView(v)} style={{
            flex: 1, padding: "12px 0", background: "none", border: "none",
            borderBottom: view === v ? "3px solid #00aeef" : "3px solid transparent",
            color: view === v ? "#00aeef" : "#5a86a8",
            fontFamily: "'Bebas Neue', sans-serif", fontSize: 16, letterSpacing: 3,
            textTransform: "uppercase", cursor: "pointer",
          }}>
            {v === "setup" ? "Setup" : v === "race" ? "Race" : "Results"}
          </button>
        ))}
      </div>

      <div style={{ maxWidth: 640, margin: "0 auto", padding: "16px 16px 60px" }}>

        {/* STOPWATCH — sticky */}
        <div style={{ background: "#0c2240", borderRadius: 8, border: "1px solid rgba(0,174,239,0.3)", padding: "14px 20px", marginBottom: 16, textAlign: "center", position: "sticky", top: 0, zIndex: 100, boxShadow: "0 6px 24px rgba(0,0,0,0.6)" }}>
          <div style={{ fontFamily: "'Bebas Neue', sans-serif", fontSize: 56, letterSpacing: 4, color: "#00aeef", lineHeight: 1 }}>
            {formatTime(clockMs)}
          </div>
          <div style={{ display: "flex", gap: 10, justifyContent: "center", marginTop: 12, flexWrap: "wrap" }}>
            {!clockStarted ? (
              <button onClick={startClock} style={btnStyle("#00aeef")}>Start Clock</button>
            ) : clockRunning ? (
              <button onClick={pauseClock} style={btnStyle("#ffd166")}>Pause</button>
            ) : (
              <button onClick={resumeClock} style={btnStyle("#4ade80")}>Resume</button>
            )}
            <button onClick={resetClock} style={btnStyle("#5a86a8", true)}>Reset Clock</button>
            {!resetConfirm ? (
              <button onClick={() => setResetConfirm(true)} style={btnStyle("#f4742b", true)}>Reset Timers</button>
            ) : (
              <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                <span style={{ fontSize: 12, color: "#f4742b" }}>Keep names, clear all times?</span>
                <button onClick={resetTimers} style={{ ...btnStyle("#f4742b"), padding: "6px 12px", fontSize: 12 }}>Yes</button>
                <button onClick={() => setResetConfirm(false)} style={{ ...btnStyle("#5a86a8", true), padding: "6px 12px", fontSize: 12 }}>No</button>
              </div>
            )}
          </div>
        </div>

        {/* SETUP VIEW */}
        {view === "setup" && (
          <div>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 3, textTransform: "uppercase", color: "#5a86a8", marginBottom: 10 }}>
              Athletes &nbsp;&mdash;&nbsp; <span style={{ color: "#48cae4" }}>Snake start, 10s apart</span>
            </div>
            {athletes.map((ath, i) => (
              <div key={ath.id} style={{ display: "flex", gap: 8, alignItems: "center", marginBottom: 8 }}>
                <div style={{ display: "flex", flexDirection: "column", gap: 2, flexShrink: 0 }}>
                  <button onClick={() => moveAthlete(i, -1)} disabled={i === 0} style={{
                    background: "none", border: "none", color: i === 0 ? "#1a3a5c" : "#5a86a8",
                    cursor: i === 0 ? "default" : "pointer", fontSize: 12, padding: "1px 4px", lineHeight: 1,
                  }}>▲</button>
                  <button onClick={() => moveAthlete(i, 1)} disabled={i === athletes.length - 1} style={{
                    background: "none", border: "none", color: i === athletes.length - 1 ? "#1a3a5c" : "#5a86a8",
                    cursor: i === athletes.length - 1 ? "default" : "pointer", fontSize: 12, padding: "1px 4px", lineHeight: 1,
                  }}>▼</button>
                </div>
                <div style={{ background: "#0c2240", borderRadius: 4, width: 30, height: 30, display: "flex", alignItems: "center", justifyContent: "center", fontFamily: "'Bebas Neue'", fontSize: 18, color: "#00aeef", flexShrink: 0 }}>{i + 1}</div>
                <input
                  value={ath.name}
                  onChange={e => updateName(i, e.target.value)}
                  placeholder={`Athlete ${i + 1} name`}
                  style={{ flex: 1, background: "#0c2240", border: "1px solid rgba(0,174,239,0.25)", borderRadius: 4, padding: "10px 14px", color: "#e8f4fb", fontSize: 14, outline: "none" }}
                />
                {athletes.length > 1 && (
                  <button onClick={() => removeAthlete(i)} style={{ background: "none", border: "none", color: "#5a86a8", fontSize: 18, cursor: "pointer", padding: "0 6px" }}>&times;</button>
                )}
              </div>
            ))}
            <div style={{ display: "flex", gap: 10, marginTop: 12, flexWrap: "wrap" }}>
              <button onClick={addAthlete} style={btnStyle("#48cae4", true)}>+ Add Athlete</button>
              <button onClick={startRace} style={btnStyle("#00aeef")}>Go to Race &rarr;</button>
            </div>
            <div style={{ marginTop: 16, background: "#0a3358", borderLeft: "3px solid #00aeef", borderRadius: 4, padding: "10px 14px", fontSize: 12, color: "#7aa8c8" }}>
              Snake start: tap <strong style={{ color: "#48cae4" }}>Send Off</strong> for each athlete as they dive in, then tap their segment buttons as they complete each leg. Use <strong style={{ color: "#f4742b" }}>Reset Timers</strong> to clear all times while keeping names.
            </div>
          </div>
        )}

        {/* RACE VIEW */}
        {view === "race" && (
          <div>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 3, textTransform: "uppercase", color: "#5a86a8", marginBottom: 10 }}>
              {athletes.length} Athletes &nbsp;&mdash;&nbsp; Tap to log splits
            </div>
            {athletes.map((ath, i) => {
              const next = nextUnloggedSeg(ath);
              const done = ath.finished;
              const elapsed = ath.startOffset !== null ? clockMs - ath.startOffset : null;
              return (
                <div key={ath.id} style={{
                  background: "#0c2240", borderRadius: 8, marginBottom: 10,
                  border: `1px solid ${done ? "#4ade80" : ath.started ? "rgba(0,174,239,0.3)" : "rgba(255,255,255,0.06)"}`,
                  overflow: "hidden",
                }}>
                  <div style={{ display: "flex", alignItems: "center", justifyContent: "space-between", padding: "10px 14px", borderBottom: "1px solid rgba(255,255,255,0.06)" }}>
                    <div style={{ display: "flex", alignItems: "center", gap: 10 }}>
                      <div style={{ fontFamily: "'Bebas Neue'", fontSize: 22, color: done ? "#4ade80" : "#00aeef", lineHeight: 1, minWidth: 24 }}>{i + 1}</div>
                      <div>
                        <div style={{ fontWeight: 700, fontSize: 14, color: "#e8f4fb" }}>{ath.name}</div>
                        {ath.started && <div style={{ fontSize: 11, color: "#5a86a8" }}>Elapsed: <span style={{ color: "#48cae4" }}>{formatElapsed(elapsed)}</span></div>}
                      </div>
                    </div>
                    <div style={{ display: "flex", gap: 6, alignItems: "center" }}>
                      {done && <span style={{ fontSize: 11, fontWeight: 700, color: "#4ade80", letterSpacing: 1 }}>DONE</span>}
                      {!ath.started && (
                        <button onClick={() => sendOff(i)} style={{ ...btnStyle("#00aeef"), padding: "6px 14px", fontSize: 12 }}>
                          Send Off
                        </button>
                      )}
                    </div>
                  </div>
                  {ath.started && (
                    <div style={{ padding: "10px 14px", display: "flex", flexWrap: "wrap", gap: 6 }}>
                      {SEGMENTS.map((seg, si) => {
                        const logged = ath.splits[si] !== null;
                        const isNext = si === next;
                        const dur = segmentDuration(ath, si);
                        return (
                          <button key={si} onClick={() => !logged && isNext && logSplit(i, si)}
                            style={{
                              padding: "6px 12px", borderRadius: 4, border: "none",
                              cursor: logged ? "default" : isNext ? "pointer" : "not-allowed",
                              background: logged ? `${segColors[si]}22` : isNext ? segColors[si] : "rgba(255,255,255,0.04)",
                              color: logged ? segColors[si] : isNext ? "#071829" : "#3a6080",
                              fontWeight: 700, fontSize: 12, letterSpacing: 0.5, transition: "all 0.15s",
                            }}>
                            {seg}{logged && dur !== null ? ` · ${formatElapsed(dur)}` : ""}
                          </button>
                        );
                      })}
                    </div>
                  )}
                </div>
              );
            })}
            {allFinished && (
              <button onClick={() => setView("results")} style={{ ...btnStyle("#4ade80"), width: "100%", marginTop: 8, fontSize: 14 }}>
                View Results &rarr;
              </button>
            )}
          </div>
        )}

        {/* RESULTS VIEW */}
        {view === "results" && (
          <div>
            <div style={{ fontSize: 11, fontWeight: 700, letterSpacing: 3, textTransform: "uppercase", color: "#5a86a8", marginBottom: 12 }}>
              Final Results
            </div>
            {!anyStarted ? (
              <div style={{ textAlign: "center", color: "#5a86a8", fontSize: 13, padding: "40px 20px" }}>
                No race data yet — head to <strong style={{ color: "#00aeef" }}>Race</strong> to start timing.
              </div>
            ) : (
              <div style={{ overflowX: "auto" }}>
                <table style={{ width: "100%", borderCollapse: "collapse", fontSize: 12 }}>
                  <thead>
                    <tr style={{ borderBottom: "1px solid rgba(255,255,255,0.1)" }}>
                      <th style={thStyle("#5a86a8")}>Place</th>
                      <th style={{ ...thStyle("#5a86a8"), textAlign: "left" }}>Athlete</th>
                      {SEGMENTS.map((seg, si) => <th key={si} style={thStyle(segColors[si])}>{seg}</th>)}
                      <th style={thStyle("#4ade80")}>Total</th>
                    </tr>
                  </thead>
                  <tbody>
                    {sorted.map((ath, place) => {
                      const tot = totalTime(ath);
                      return (
                        <tr key={ath.id} style={{ borderBottom: "1px solid rgba(255,255,255,0.05)", background: place === 0 && tot !== null ? "rgba(74,222,128,0.05)" : "transparent" }}>
                          <td style={{ padding: "10px 10px", fontFamily: "'Bebas Neue'", fontSize: 20, color: place === 0 ? "#4ade80" : place === 1 ? "#ffd166" : place === 2 ? "#48cae4" : "#5a86a8" }}>{place + 1}</td>
                          <td style={{ padding: "10px 10px", fontWeight: 700, color: "#e8f4fb", whiteSpace: "nowrap" }}>{ath.name}</td>
                          {SEGMENTS.map((_, si) => {
                            const dur = segmentDuration(ath, si);
                            return <td key={si} style={{ padding: "10px 6px", textAlign: "center", color: segColors[si], fontWeight: 600, whiteSpace: "nowrap" }}>{dur !== null ? formatElapsed(dur) : "--"}</td>;
                          })}
                          <td style={{ padding: "10px 10px", textAlign: "center", fontWeight: 800, color: "#4ade80", whiteSpace: "nowrap" }}>{tot !== null ? formatElapsed(tot) : "--"}</td>
                        </tr>
                      );
                    })}
                  </tbody>
                </table>
              </div>
            )}
          </div>
        )}

      </div>
    </div>
  );
}

function btnStyle(color, outline = false) {
  return {
    background: outline ? "transparent" : color,
    border: `2px solid ${color}`,
    color: outline ? color : "#071829",
    padding: "10px 20px",
    borderRadius: 4,
    fontWeight: 700,
    fontSize: 13,
    letterSpacing: 1,
    cursor: "pointer",
  };
}

function thStyle(color) {
  return { textAlign: "center", padding: "8px 6px", color, fontWeight: 700, letterSpacing: 1, fontSize: 10, textTransform: "uppercase" };
}
