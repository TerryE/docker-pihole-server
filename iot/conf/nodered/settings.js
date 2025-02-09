module.exports = {

  credentialSecret:  'IN.TE.SPERANT.DOMINE',
  flowFile:          'flows.json',
  flowFilePretty:    true,
  userDir:           '/usr/local/data/nodered',
  nodesDir:          '/usr/local/data/nodered/nodes',
  requireHttps:      false,
  //httpNodeAuth:    {user:"",pass:""},
  //httpStaticAuth:  {user:"",pass:""},

  mqttReconnectTime:   15000,
  serialReconnectTime: 15000,
  debugMaxLength:      1000,

  adminAuth: {
      type: "credentials",
      users: [{
          username: "terry",
          password: "$2b$08$0oCtrNZPbQ46PjU2KTRbr.3jbOiQYGVgPMmKC5tmh2sCdbrBZlBey",
          permissions: "*"
      }]
  },

  //https: { () => { return {
  //       key:  require("fs").readFileSync('privkey.pem'),
  //       cert: require("fs").readFileSync('cert.pem'),
  //   }; },
  //httpsRefreshInterval : 12,  // Hours
  //requireHttps: true,

  // Diagnostics options if enabled, diagnostics data will  be available at
  // http://localhost:1880/diagnostics.  If ui is true`, then the action
  // `show-system-info` is e available to logged in users of node-red editor
  diagnostics: { enabled: true, ui: true },

  runtimeState: { enabled: false, ui: false },
  
  logging: { console: { level: "info", metrics: false, audit: false }, },

  functionExternalModules: true,
  functionTimeout: 0,
  functionGlobalContext: {},

  uiPort: 80,
  ui: { path: "ui" },
  
  apiMaxLength: '5mb',

  editorTheme: {
    projects: { enabled: false },
  },
  codeEditor: {
     lib: 'monaco', 
     options: {
        formatOnPaste: false,
        useTabStops: true,
        colorDecorators: true,
        fontSize: 14,
        "bracketPairColorization.enabled": true,
      },
  },  
};
