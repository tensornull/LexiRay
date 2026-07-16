import { useEffect, useMemo, useRef, useState } from "react";
import {
  AppWindow,
  ArrowCircleRight,
  ArrowsLeftRight,
  ArrowsOut,
  BookOpen,
  CaretDown,
  CaretRight,
  ChatText,
  Check,
  CheckCircle,
  Circle,
  ClockCounterClockwise,
  Copy,
  CursorText,
  Gear,
  Globe,
  HardDrives,
  Keyboard,
  MinusCircle,
  Monitor,
  Plus,
  PushPin,
  Scan,
  Selection,
  ShieldCheck,
  SidebarSimple,
  SpeakerHigh,
  SpeakerSlash,
  SquaresFour,
  TextT,
  Trash,
  Wrench,
  X,
} from "@phosphor-icons/react";
import {
  historyItems,
  initialProviders,
  mockTranslation,
  providerCatalog,
} from "./data.js";

const sections = [
  { id: "dashboard", label: "Dashboard", icon: SquaresFour },
  { id: "providers", label: "Providers", icon: MinusCircle },
  { id: "settings", label: "Settings", icon: Gear },
];

const selectionSample = "This selected text was captured from another application.";
const ocrSample = "Text recognized inside the OCR region.";

function IconButton({ label, active = false, children, onClick, testId, disabled = false }) {
  return (
    <button
      className={`icon-button ${active ? "is-active" : ""}`}
      aria-label={label}
      title={label}
      onClick={onClick}
      data-testid={testId}
      disabled={disabled}
    >
      {children}
    </button>
  );
}

function Pill({ icon: Icon, children, tone = "neutral" }) {
  return (
    <span className={`pill pill-${tone}`}>
      {Icon ? <Icon size={13} weight="bold" /> : null}
      {children}
    </span>
  );
}

function SectionCard({ title, icon: Icon, children, className = "" }) {
  return (
    <section className={`section-card ${className}`}>
      <h2>
        <Icon size={18} weight="regular" />
        {title}
      </h2>
      {children}
    </section>
  );
}

function Toggle({ checked, onChange, label, testId }) {
  return (
    <label className="toggle-row">
      <span>{label}</span>
      <input
        type="checkbox"
        checked={checked}
        onChange={(event) => onChange(event.target.checked)}
        data-testid={testId}
      />
      <span className="toggle-track" aria-hidden="true">
        <span className="toggle-thumb" />
      </span>
    </label>
  );
}

function WindowChrome({ title, section, onToggleSidebar }) {
  return (
    <div className="window-toolbar">
      <div className="traffic-lights" aria-label="macOS window controls">
        <Circle size={14} weight="fill" color="#ff5f57" />
        <Circle size={14} weight="fill" color="#febc2e" />
        <Circle size={14} weight="fill" color="#28c840" />
      </div>
      <button className="sidebar-toggle" aria-label="Toggle sidebar" onClick={onToggleSidebar}>
        <SidebarSimple size={19} />
      </button>
      <strong className="window-title" data-testid="window-title">
        {title || section}
      </strong>
    </div>
  );
}

function Dashboard({
  source,
  setSource,
  onTranslate,
  onSelection,
  onOCR,
  recentResult,
  translating,
  language1,
  setLanguage1,
  language2,
  setLanguage2,
  autoSwitch,
  setAutoSwitch,
}) {
  const submit = () => {
    if (source.trim()) onTranslate(source, "Manual");
  };

  return (
    <div className="page dashboard-page" data-testid="dashboard-page">
      <header className="product-header">
        <img src="/assets/lexiray-app-icon.png" alt="LexiRay" />
        <div>
          <h1>LexiRay</h1>
          <p>System Dictionary</p>
        </div>
        <div className="header-pills">
          <Pill icon={ArrowsLeftRight}>auto -&gt; zh-Hans</Pill>
          <Pill icon={Keyboard}>Control-Option-Shift-A</Pill>
          <Pill icon={Scan}>Control-Option-Shift-S</Pill>
        </div>
      </header>

      <SectionCard title="Translate" icon={CursorText}>
        <textarea
          className="dashboard-editor"
          placeholder="Type or edit source text"
          value={source}
          onChange={(event) => setSource(event.target.value)}
          onKeyDown={(event) => {
            if ((event.metaKey || event.ctrlKey) && event.key === "Enter") submit();
          }}
          data-testid="dashboard-source"
        />
        <div className="button-row">
          <button className="button primary" onClick={submit} disabled={!source.trim()} data-testid="dashboard-translate">
            <ArrowCircleRight size={17} weight="fill" /> Translate
          </button>
          <button className="button" onClick={onSelection} data-testid="translate-selection">
            <Selection size={17} /> Selection
          </button>
          <button className="button" onClick={onOCR} data-testid="translate-ocr">
            <Scan size={17} /> OCR Region
          </button>
        </div>
      </SectionCard>

      <SectionCard title="Languages" icon={Globe}>
        <div className="language-grid">
          <input aria-label="Language 1" value={language1} onChange={(event) => setLanguage1(event.target.value)} />
          <ArrowsLeftRight size={18} />
          <input aria-label="Language 2" value={language2} onChange={(event) => setLanguage2(event.target.value)} />
        </div>
        <label className="check-row">
          <input type="checkbox" checked={autoSwitch} onChange={(event) => setAutoSwitch(event.target.checked)} />
          <span><Check size={13} weight="bold" /></span>
          Auto switch
        </label>
      </SectionCard>

      <SectionCard title="Recent Result" icon={ChatText}>
        <div className={`recent-result ${recentResult ? "has-result" : ""}`}>
          {translating ? (
            <div className="empty-result"><span className="spinner" /> <div><strong>Translating</strong><p>{source}</p></div></div>
          ) : recentResult ? (
            <div className="result-copy">
              <div className="provider-heading"><BookOpen size={18} /><strong>System Dictionary</strong></div>
              <p>{recentResult}</p>
            </div>
          ) : (
            <div className="empty-result"><Keyboard size={28} /><div><strong>Ready</strong><p>No recent translation.</p></div></div>
          )}
        </div>
      </SectionCard>
    </div>
  );
}

function Providers({ providers, setProviders }) {
  const [menuOpen, setMenuOpen] = useState(false);
  const addProvider = (catalogItem) => {
    const id = `${catalogItem.kind.toLowerCase().replace(/[^a-z0-9]+/g, "-")}-${Date.now()}`;
    setProviders((items) => [...items, { ...catalogItem, id, enabled: true, builtIn: false }]);
    setMenuOpen(false);
  };

  const updateProvider = (id, patch) => {
    setProviders((items) => items.map((item) => (item.id === id ? { ...item, ...patch } : item)));
  };

  return (
    <div className="page" data-testid="providers-page">
      <header className="page-header">
        <h1><HardDrives size={24} /> Providers</h1>
        <div className="page-actions">
          <Pill icon={MinusCircle}>{providers.filter((provider) => provider.enabled).map((provider) => provider.name).join(", ") || "No active provider"}</Pill>
          <div className="menu-wrap">
            <button className="button" onClick={() => setMenuOpen((value) => !value)} data-testid="add-provider">
              <Plus size={17} /> Add Provider <CaretDown size={14} />
            </button>
            {menuOpen ? (
              <div className="provider-menu" role="menu" data-testid="provider-menu">
                {providerCatalog.map((provider, index) => (
                  <button key={provider.kind} onClick={() => addProvider(provider)} role="menuitem" data-testid={`provider-option-${index}`}>
                    <img src={provider.icon} alt="" />
                    <span><strong>{provider.kind}</strong><small>{provider.model}</small></span>
                  </button>
                ))}
              </div>
            ) : null}
          </div>
        </div>
      </header>

      <div className="provider-grid">
        {providers.map((provider) => (
          <section className="provider-card" key={provider.id}>
            <header>
              {provider.icon ? <img src={provider.icon} alt="" /> : <BookOpen size={20} />}
              <strong>{provider.name}</strong>
              {!provider.builtIn && provider.name !== provider.kind ? <Pill>{provider.kind}</Pill> : null}
              <span className="spacer" />
              <IconButton
                label="Remove provider"
                disabled={provider.builtIn}
                onClick={() => setProviders((items) => items.filter((item) => item.id !== provider.id))}
              >
                <Trash size={16} />
              </IconButton>
            </header>

            <Toggle
              label="Enabled"
              checked={provider.enabled}
              onChange={(enabled) => updateProvider(provider.id, { enabled })}
            />

            <input
              aria-label={`${provider.name} Display Name`}
              placeholder="Display Name"
              value={provider.customName || ""}
              onChange={(event) => updateProvider(provider.id, { customName: event.target.value, name: event.target.value || provider.kind })}
            />

            {provider.builtIn ? (
              <p className="helper">Uses the macOS system dictionary.</p>
            ) : (
              <>
                <label>Base URL<input value={provider.baseURL} onChange={(event) => updateProvider(provider.id, { baseURL: event.target.value })} /></label>
                <label>Model<input value={provider.model} onChange={(event) => updateProvider(provider.id, { model: event.target.value })} /></label>
                <label>API key<input type="password" value="mock-provider-key" readOnly aria-readonly="true" /></label>
                <p className="key-state saved">Mock key configured</p>
              </>
            )}
          </section>
        ))}
      </div>
    </div>
  );
}

function Settings({ settings, setSettings, onResetProviders }) {
  const [notice, setNotice] = useState("");
  const patch = (value) => setSettings((current) => ({ ...current, ...value }));
  const reportMockAction = (message) => setNotice(message);
  const hotKeyStatusDetail = (status) => ({
    registered: "Registered",
    conflict: "Shortcut is already in use.",
    invalid: "Shortcut is invalid.",
    systemError: "Registration failed.",
  })[status];
  const hotKeyRow = (title, shortcut, status, testId, onReset) => (
    <div className="setting-stack">
      <div className="setting-line"><span>{title}</span><button className="button hotkey" onClick={() => reportMockAction(`${title} shortcut editor opened (mock).`)}>{shortcut}</button><button className="button compact" onClick={onReset}>Reset</button></div>
      <p className={`setting-detail ${status === "registered" ? "" : "warning"}`} data-testid={testId}>{hotKeyStatusDetail(status)}</p>
    </div>
  );
  return (
    <div className="page settings-page" data-testid="settings-page">
      {notice ? <p className="settings-action-toast" role="status" data-testid="settings-action-status"><CheckCircle size={14} weight="fill" />{notice}</p> : null}
      <SectionCard title="App" icon={AppWindow}>
        <Toggle label="Show menu bar icon" checked={settings.menuBar} onChange={(menuBar) => patch({ menuBar })} />
        <Toggle label="Start at login" checked={settings.startAtLogin} onChange={(startAtLogin) => patch({ startAtLogin })} />
        <p className="setting-detail" data-testid="start-at-login-status">{settings.startAtLogin ? "Enabled" : "Off"}</p>
      </SectionCard>

      <SectionCard title="Translation" icon={TextT}>
        <label className="setting-line"><span>Auto copy</span><select value={settings.autoCopy} onChange={(event) => patch({ autoCopy: event.target.value })}><option>Off</option><option>First Provider Result</option></select></label>
      </SectionCard>

      <SectionCard title="Hotkeys" icon={Keyboard}>
        {hotKeyRow("Translate selection", "Control-Option-Shift-A", settings.selectionHotKeyStatus, "selection-hotkey-status", () => { patch({ selectionHotKeyStatus: "registered" }); reportMockAction("Selection hotkey reset."); })}
        {hotKeyRow("OCR region", "Control-Option-Shift-S", settings.ocrHotKeyStatus, "ocr-hotkey-status", () => { patch({ ocrHotKeyStatus: "registered" }); reportMockAction("OCR hotkey reset."); })}
        <button className="button" onClick={() => { patch({ selectionHotKeyStatus: "registered", ocrHotKeyStatus: "registered" }); reportMockAction("Default hotkeys restored."); }}>Restore Default Hotkeys</button>
      </SectionCard>

      <SectionCard title="Floating Panel" icon={AppWindow}>
        <label className="setting-line"><span>Default position</span><select value={settings.panelPosition} onChange={(event) => patch({ panelPosition: event.target.value })}><option>Screen Center</option><option>Near Cursor</option><option>Remember Last Position</option></select></label>
      </SectionCard>

      <SectionCard title="History" icon={ClockCounterClockwise}>
        <label className="setting-line"><span>Maximum saved items</span><input className="number-input" type="number" min="1" max="100" value={settings.historyLimit} onChange={(event) => patch({ historyLimit: event.target.value })} /></label>
      </SectionCard>

      <SectionCard title="App Identity" icon={ShieldCheck}>
        <div className="identity-status"><CheckCircle size={20} weight="fill" /><div><strong>Stable</strong><p>LexiRay Local Development</p></div></div>
        <dl><div><dt>Authority</dt><dd>LexiRay Local Development</dd></div><div><dt>Path</dt><dd>/Applications/LexiRay.app</dd></div></dl>
        <div className="button-row"><button className="button" onClick={() => reportMockAction("Install location opened (mock).")}>Open Install Location</button><button className="button" onClick={() => reportMockAction("Privacy settings opened (mock).")}>Open Privacy Settings</button><button className="button" onClick={() => reportMockAction("Mock diagnostics copied.")}>Copy Diagnostics</button></div>
      </SectionCard>

      <SectionCard title="Permissions" icon={ShieldCheck}>
        {[
          ["Accessibility", true],
          ["Screen Recording", true],
          ["Automation", false],
        ].map(([name, granted]) => <div className="permission-line" key={name}><span>{name}</span><Pill tone={granted ? "success" : "warning"}>{granted ? "Granted" : "Not granted"}</Pill>{!granted ? <button className="button compact" onClick={() => reportMockAction(`${name} settings opened (mock).`)}>Open</button> : null}</div>)}
      </SectionCard>

      <SectionCard title="Advanced" icon={Wrench}>
        <label className="setting-line"><span>Last source</span><select><option>Manual</option><option>Selection</option><option>OCR</option></select></label>
        <button className="button" onClick={() => { onResetProviders(); reportMockAction("Provider settings reset to mock defaults."); }}>Reset Provider Settings</button>
      </SectionCard>
    </div>
  );
}

function FloatingPanel({
  open,
  onClose,
  source,
  setSource,
  result,
  setResult,
  status,
  setStatus,
  sourceKind,
  setSourceKind,
  onOpenSettings,
}) {
  const [pinned, setPinned] = useState(false);
  const [expanded, setExpanded] = useState(false);
  const [sourceLanguage, setSourceLanguage] = useState("Auto: English");
  const [targetLanguage, setTargetLanguage] = useState("Auto: Simplified Chinese");
  const [speaking, setSpeaking] = useState(false);
  const [resultCollapsed, setResultCollapsed] = useState(false);
  const [copyFormat, setCopyFormat] = useState("Original Text");
  const [toast, setToast] = useState("");
  const [historyIndex, setHistoryIndex] = useState(null);
  const translationTimer = useRef(null);
  const toastTimer = useRef(null);

  useEffect(() => () => {
    window.clearTimeout(translationTimer.current);
    window.clearTimeout(toastTimer.current);
  }, []);

  useEffect(() => {
    if (!open) {
      window.clearTimeout(toastTimer.current);
      toastTimer.current = null;
      setToast("");
    }
  }, [open]);

  if (!open) return null;

  const translate = () => {
    if (!source.trim()) return;
    setHistoryIndex(null);
    setStatus("Translating");
    setResult("");
    window.clearTimeout(translationTimer.current);
    translationTimer.current = window.setTimeout(() => {
      setResult(mockTranslation(source));
      setStatus("Translated");
    }, 650);
  };

  const selectHistory = (nextIndex) => {
    if (nextIndex < 0 || nextIndex >= historyItems.length) {
      setHistoryIndex(null);
      setSource("");
      setResult("");
      setStatus("Ready");
      return;
    }
    const item = historyItems[nextIndex];
    setHistoryIndex(nextIndex);
    setSource(item.source);
    setResult(item.result);
    setSourceKind("Manual");
    setSourceLanguage(item.sourceLanguage);
    setTargetLanguage(item.targetLanguage);
    setSpeaking(false);
    setStatus("Translated");
  };

  const previousHistory = () => selectHistory(historyIndex === null ? historyItems.length - 1 : historyIndex - 1);
  const nextHistory = () => selectHistory(historyIndex === null ? historyItems.length : historyIndex + 1);

  const copyResult = () => {
    if (!result) return;
    // This isolated prototype exercises product feedback without touching the
    // user's real clipboard or allowing an async completion to outlive close.
    setToast("Copied");
    window.clearTimeout(toastTimer.current);
    toastTimer.current = window.setTimeout(() => setToast(""), 1300);
  };

  return (
    <div className="panel-stage" data-testid="floating-panel-stage">
      <section className={`floating-panel ${expanded ? "is-expanded" : ""}`} data-testid="floating-panel">
        {toast ? <div className="copy-toast"><CheckCircle size={15} weight="fill" /> {toast}</div> : null}
        <header className="panel-header">
          <strong>{historyIndex === null ? "LexiRay" : `History ${historyItems.length - historyIndex}/${historyItems.length}`}</strong>
          <Pill icon={status === "Translated" ? CheckCircle : undefined} tone={status === "Translated" ? "accent" : "neutral"}>{status}</Pill>
          <span className="spacer" />
          <IconButton label="Settings" onClick={onOpenSettings} testId="panel-settings"><Gear size={17} /></IconButton>
          <IconButton label={pinned ? "Unpin" : "Pin"} active={pinned} onClick={() => setPinned((value) => !value)} testId="panel-pin"><PushPin size={17} weight={pinned ? "fill" : "regular"} /></IconButton>
          <IconButton label={expanded ? "Collapse" : "Expand"} onClick={() => setExpanded((value) => !value)} testId="panel-expand"><ArrowsOut size={17} /></IconButton>
          <IconButton label="Close" onClick={onClose} testId="panel-close"><X size={18} /></IconButton>
        </header>

        <section className="composer-card">
          <div className="composer-toolbar">
            <span className="source-label">Source</span>
            <select value={sourceLanguage} onChange={(event) => { setSourceLanguage(event.target.value); setHistoryIndex(null); }} aria-label="Source language">
              <option>Auto: English</option><option>English</option><option>Japanese</option><option>Simplified Chinese</option>
            </select>
            <IconButton label="Swap translation direction" onClick={() => { setSourceLanguage(targetLanguage); setTargetLanguage(sourceLanguage); }} disabled={!source.trim()}>
              <ArrowsLeftRight size={17} />
            </IconButton>
            <select value={targetLanguage} onChange={(event) => { setTargetLanguage(event.target.value); setHistoryIndex(null); }} aria-label="Target language">
              <option>Auto: Simplified Chinese</option><option>Simplified Chinese</option><option>English</option><option>Japanese</option>
            </select>
            <Pill icon={Keyboard} tone="accent">{sourceKind}</Pill>
            <span className="spacer" />
            <IconButton label={speaking ? "Stop source speech" : "Speak source"} active={speaking} disabled={!source.trim()} onClick={() => setSpeaking((value) => !value)}>
              {speaking ? <SpeakerSlash size={17} /> : <SpeakerHigh size={17} />}
            </IconButton>
            {source.trim() ? <IconButton label="Clear" onClick={() => { setSource(""); setResult(""); setStatus("Ready"); setHistoryIndex(null); setSpeaking(false); }}><X size={17} weight="fill" /></IconButton> : null}
            <button className="button primary panel-translate" onClick={translate} disabled={!source.trim()} data-testid="panel-retranslate">
              <ArrowCircleRight size={17} weight="fill" /> {result ? "Retranslate" : "Translate"}
            </button>
          </div>
          <textarea
            value={source}
            placeholder="Type or paste text   ⌘↵   ↑↓ History"
            onChange={(event) => { setSource(event.target.value); setHistoryIndex(null); }}
            onKeyDown={(event) => {
              if ((event.metaKey || event.ctrlKey) && event.key === "Enter") translate();
              if (event.key === "ArrowUp" && !source.trim()) { event.preventDefault(); previousHistory(); }
              if (event.key === "ArrowDown" && historyIndex !== null) { event.preventDefault(); nextHistory(); }
            }}
            data-testid="panel-source"
          />
        </section>

        {status === "Translating" || result ? (
          <section className="panel-result-card">
            <header>
              <BookOpen size={20} />
              <strong>System Dictionary</strong>
              <span className="spacer" />
              {result ? (
                <>
                  <IconButton label="Copy" onClick={copyResult} testId="copy-result"><Copy size={17} /></IconButton>
                  <span className="copy-format-wrap" title={`Copy format: ${copyFormat}`}>
                    <CaretDown size={15} />
                    <select className="copy-format" value={copyFormat} onChange={(event) => setCopyFormat(event.target.value)} aria-label="Copy format">
                      <option>Original Text</option><option>Plain Text</option><option>Markdown</option><option>HTML</option>
                    </select>
                  </span>
                  <IconButton label={speaking ? "Stop" : "Speak"} active={speaking} onClick={() => setSpeaking((value) => !value)}>{speaking ? <SpeakerSlash size={17} /> : <SpeakerHigh size={17} />}</IconButton>
                </>
              ) : <Pill>Translating</Pill>}
              <IconButton label={resultCollapsed ? "Enable Provider" : "Disable Provider"} onClick={() => setResultCollapsed((value) => !value)}>
                {resultCollapsed ? <CaretRight size={17} /> : <CaretDown size={17} />}
              </IconButton>
            </header>
            {!resultCollapsed ? (
              status === "Translating" ? <div className="streaming-line"><span className="spinner" /> Waiting for System Dictionary...</div> : <p data-testid="panel-result">{result}</p>
            ) : null}
          </section>
        ) : (
          <section className="panel-result-card standby-card">
            <header><BookOpen size={18} /><strong>System Dictionary</strong><span className="spacer" /><Pill tone="accent">Stand by</Pill></header>
          </section>
        )}
      </section>
    </div>
  );
}

export function App() {
  const [section, setSection] = useState("dashboard");
  const [sidebarOpen, setSidebarOpen] = useState(true);
  const [mainSource, setMainSource] = useState("");
  const [panelSource, setPanelSource] = useState("");
  const [panelResult, setPanelResult] = useState("");
  const [recentResult, setRecentResult] = useState("");
  const [panelStatus, setPanelStatus] = useState("Ready");
  const [panelOpen, setPanelOpen] = useState(false);
  const [sourceKind, setSourceKind] = useState("Manual");
  const [translating, setTranslating] = useState(false);
  const [language1, setLanguage1] = useState("en");
  const [language2, setLanguage2] = useState("zh-Hans");
  const [autoSwitch, setAutoSwitch] = useState(true);
  const [providers, setProviders] = useState(initialProviders);
  const [settings, setSettings] = useState({
    menuBar: true,
    startAtLogin: false,
    selectionHotKeyStatus: "registered",
    ocrHotKeyStatus: "registered",
    autoCopy: "Off",
    panelPosition: "Screen Center",
    historyLimit: 100,
  });
  const translationTimer = useRef(null);

  useEffect(() => () => window.clearTimeout(translationTimer.current), []);

  const currentSection = useMemo(() => sections.find((item) => item.id === section), [section]);

  const openTranslation = (source, kind) => {
    setSourceKind(kind);
    setPanelSource(source);
    setPanelResult("");
    setPanelStatus("Translating");
    setPanelOpen(true);
    setTranslating(true);
    window.clearTimeout(translationTimer.current);
    translationTimer.current = window.setTimeout(() => {
      const translated = mockTranslation(source);
      setPanelResult(translated);
      setRecentResult(translated);
      setPanelStatus("Translated");
      setTranslating(false);
    }, 700);
  };

  return (
    <main className="prototype-stage">
      <div className={`mac-window ${sidebarOpen ? "" : "sidebar-collapsed"}`} aria-label="LexiRay application window">
        <WindowChrome section={currentSection.label} onToggleSidebar={() => setSidebarOpen((value) => !value)} />
        <aside className="sidebar" aria-label="Main navigation">
          {sections.map(({ id, label, icon: Icon }) => (
            <button key={id} className={section === id ? "selected" : ""} onClick={() => setSection(id)} data-testid={`nav-${id}`}>
              <Icon size={18} weight="regular" />
              <span>{label}</span>
            </button>
          ))}
        </aside>
        <div className="window-detail">
          {section === "dashboard" ? (
            <Dashboard
              source={mainSource}
              setSource={setMainSource}
              onTranslate={openTranslation}
              onSelection={() => openTranslation(selectionSample, "Accessibility")}
              onOCR={() => openTranslation(ocrSample, "OCR")}
              recentResult={recentResult}
              translating={translating}
              language1={language1}
              setLanguage1={setLanguage1}
              language2={language2}
              setLanguage2={setLanguage2}
              autoSwitch={autoSwitch}
              setAutoSwitch={setAutoSwitch}
            />
          ) : null}
          {section === "providers" ? <Providers providers={providers} setProviders={setProviders} /> : null}
          {section === "settings" ? <Settings settings={settings} setSettings={setSettings} onResetProviders={() => setProviders(initialProviders)} /> : null}
        </div>
      </div>

      <FloatingPanel
        open={panelOpen}
        onClose={() => setPanelOpen(false)}
        source={panelSource}
        setSource={setPanelSource}
        result={panelResult}
        setResult={setPanelResult}
        status={panelStatus}
        setStatus={setPanelStatus}
        sourceKind={sourceKind}
        setSourceKind={setSourceKind}
        onOpenSettings={() => { setPanelOpen(false); setSection("settings"); }}
      />
    </main>
  );
}
