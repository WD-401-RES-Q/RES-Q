const test = require('node:test');
const assert = require('node:assert/strict');

test('functions module exports expected handlers', () => {
  const handlers = require('../lib/index.js');

  const expectedExports = [
    'registerUserEncrypted',
    'decryptUserData',
    'getOwnDecryptedProfile',
    'getDecryptedUsers',
    'syncApprovedUsersEncryption',
    'cleanupOldReports',
    'sendPushOnAnnouncementCreate',
    'sendPushOnReportCreate',
    'sendPushOnResponderDeployment',
  ];

  for (const name of expectedExports) {
    assert.ok(
      Object.prototype.hasOwnProperty.call(handlers, name),
      `Missing export: ${name}`,
    );
    assert.ok(
      typeof handlers[name] === 'function' || typeof handlers[name] === 'object',
      `Unexpected export type for ${name}`,
    );
  }
});
