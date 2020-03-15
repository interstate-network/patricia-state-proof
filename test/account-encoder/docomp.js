const fs = require('fs');
const path = require('path');
const compile = require('../compile');

const results = compile(__dirname, 'Test', path.join(__dirname, '..', '..'));
fs.writeFileSync(path.join(__dirname, 'standard.json'), JSON.stringify(results, null, 2));