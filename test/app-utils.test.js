const test = require('node:test');
const assert = require('node:assert/strict');

const {
  filterApps,
  groupAppsByLetter,
  buildFolderEntries,
  applyManualAppGroups,
  sortEntriesByOrder,
} = require('../app-utils.js');

test('filterApps matches app names case-insensitively', () => {
  const apps = [
    { name: 'Chrome', path: '/Applications/Chrome.app' },
    { name: 'Visual Studio Code', path: '/Applications/Visual Studio Code.app' },
    { name: 'Terminal', path: '/Applications/Utilities/Terminal.app' },
  ];

  assert.deepEqual(filterApps(apps, 'code'), [apps[1]]);
  assert.deepEqual(filterApps(apps, 'CHROME'), [apps[0]]);
  assert.deepEqual(filterApps(apps, 'terminal'), [apps[2]]);
});

test('filterApps returns all apps when query is empty and no match when query does not fit', () => {
  const apps = [
    { name: 'Chrome', path: '/Applications/Chrome.app' },
  ];

  assert.deepEqual(filterApps(apps, ''), apps);
  assert.deepEqual(filterApps(apps, 'music'), []);
});

test('groupAppsByLetter groups apps by first letter and keeps # for non-alpha', () => {
  const apps = [
    { name: 'Chrome', path: '/Applications/Chrome.app' },
    { name: 'App Store', path: '/Applications/App Store.app' },
    { name: '1Password', path: '/Applications/1Password.app' },
    { name: 'Terminal', path: '/Applications/Utilities/Terminal.app' },
  ];

  const grouped = groupAppsByLetter(apps);

  assert.equal(grouped[0].label, '#');
  assert.equal(grouped[0].apps[0].name, '1Password');

  assert.equal(grouped[1].label, 'A');
  assert.equal(grouped[1].apps[0].name, 'App Store');

  assert.equal(grouped[2].label, 'C');
  assert.equal(grouped[2].apps[0].name, 'Chrome');

  assert.equal(grouped[3].label, 'T');
  assert.equal(grouped[3].apps[0].name, 'Terminal');
});

test('buildFolderEntries groups nested app bundles into folder entries and keeps single utilities as apps', () => {
  const apps = [
    { name: 'Illustrator', path: '/Applications/Adobe Illustrator 2024/Illustrator.app' },
    { name: 'Photoshop', path: '/Applications/Adobe Illustrator 2024/Photoshop.app' },
    { name: 'Chrome', path: '/Applications/Chrome.app' },
    { name: 'Activity Monitor', path: '/System/Applications/Utilities/Activity Monitor.app' },
    { name: 'Terminal', path: '/System/Applications/Utilities/Terminal.app' },
  ];

  const entries = buildFolderEntries(apps);
  const folder = entries.find(item => item && item.type === 'folder');
  const chrome = entries.find(item => item && item.name === 'Chrome');
  const utilities = entries.find(item => item && item.name === 'Utilities');

  assert.equal(folder.name, 'Adobe Illustrator 2024');
  assert.deepEqual(folder.children.map(child => child.name), ['Illustrator', 'Photoshop']);
  assert.equal(chrome.name, 'Chrome');
  assert.equal(utilities.name, 'Utilities');
  assert.deepEqual(utilities.children.map(child => child.name).sort(), ['Activity Monitor', 'Terminal']);
});

test('sortEntriesByOrder uses saved paths and keeps unspecified entries stable at the end', () => {
  const entries = [
    { name: 'A', path: '/Applications/A.app' },
    { name: 'Folder', path: '/Applications/Folder' },
    { name: 'B', path: '/Applications/B.app' },
    { name: 'C', path: '/Applications/C.app' },
  ];

  assert.deepEqual(
    sortEntriesByOrder(entries, ['/Applications/B.app', '/Applications/Folder']),
    [entries[2], entries[1], entries[0], entries[3]]
  );
});

test('applyManualAppGroups combines apps into a persistent folder entry', () => {
  const apps = [
    { name: 'Calendar', path: '/Applications/Calendar.app' },
    { name: 'Photos', path: '/Applications/Photos.app' },
    { name: 'Terminal', path: '/Applications/Terminal.app' },
  ];
  const groups = [{
    id: 'group-1',
    name: '常用',
    context: null,
    appPaths: [apps[0].path, apps[1].path],
  }];

  const entries = applyManualAppGroups(apps, groups, apps, null);

  assert.deepEqual(entries.map(entry => entry.path), [
    apps[2].path,
    'manual-folder:group-1',
  ]);
  assert.deepEqual(entries[1].children, [apps[0], apps[1]]);
});

test('applyManualAppGroups replaces an automatic folder when all members are grouped', () => {
  const apps = [
    { name: 'One', path: '/Applications/Utilities/One.app' },
    { name: 'Two', path: '/Applications/Utilities/Two.app' },
    { name: 'Browser', path: '/Applications/Browser.app' },
  ];
  const groups = [{
    id: 'group-2',
    name: '工具',
    context: null,
    appPaths: apps.map(app => app.path),
  }];

  const entries = applyManualAppGroups(
    buildFolderEntries(apps),
    groups,
    apps,
    null
  );

  assert.equal(entries.length, 1);
  assert.equal(entries[0].path, 'manual-folder:group-2');
  assert.deepEqual(entries[0].children, apps);
});
