module.exports = {
/*
 * The following configuration keys were controlled by the Node_REDadd-on.
 *
 * - adminAuth (known as users in the add-on configuration)
 * - https (ssl settings in the add-on configuration)
 * - logging.console.level (log_level in the add-on configuration)
 * - requireHttps (require_ssl setting in the add-on configuration)
 */
  credentialSecret:  'IN.TE.SPERANT.DOMINE',
  flowFile:          'flows.json',
  flowFilePretty:    true,
  userDir:           '/usr/local/data/nodered',
  nodesDir:          '/usr/local/data/nodered/nodes',
  requireHttps:      false,
  //httpNodeAuth:    {user:"",pass:""},
  //httpStaticAuth:  {user:"",pass:""},
/* 
 * If you like to change those settings, some are available via the add-on
 * settings/option in the Supervisor panel in Home Assistant.
 */
  mqttReconnectTime:   15000,
  serialReconnectTime: 15000,
  debugMaxLength:      1000,

  functionGlobalContext: {
    osModule:require('os'),
    fsModule:require('fs'),
  },
   /** To password protect the Node-RED editor and admin API, the following            
     * property can be used. See https://nodered.org/docs/security.html for details.    
     */                                                                                 
    //adminAuth: {                                                                      
    //    type: "credentials",                                                          
    //    users: [{                                                                     
    //        username: "admin",                                                        
    //        password: "$2a$08$zZWtXTja0fB1pzD4sHCMyOCMYz2Z6dNbM6tl8sJogENOMcxWV9DN.", 
    //        permissions: "*"                                                          
    //    }]                                                                            
    //},
	//
/*https: {
     key:  require("fs").readFileSync('privkey.pem'),
     cert: require("fs").readFileSync('cert.pem')
  },*/

  paletteCategories: [
    "home_assistant",
    "subflows",
    "common",
    "function",
    "network",
    "sequence",
    "parser",
    "storage"
  ],

  logging: {
    console: { metrics: false, audit: false },
  },

  editorTheme: {
    projects: { enabled: false },
  }
};
