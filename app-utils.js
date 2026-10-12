'use strict';

function normalizeQuery(query) {
  return String(query || '').trim().toLowerCase();
}

function sortAppsByName(apps) {
  return [...apps].sort((a, b) => {
    const aName = String(a && a.name ? a.name : '');
    const bName = String(b && b.name ? b.name : '');

    return aName.localeCompare(bName);
  });
}

function sortEntriesByOrder(entries, orderedPaths) {
  const orderIndex = new Map(
    (Array.isArray(orderedPaths) ? orderedPaths : [])
      .map((appPath, index) => [appPath, index])
  );

  return entries
    .map((entry, index) => ({ entry, index }))
    .sort((left, right) => {
      const leftOrder = orderIndex.get(left.entry && left.entry.path);
      const rightOrder = orderIndex.get(right.entry && right.entry.path);

      if (leftOrder === undefined && rightOrder === undefined) {
        return left.index - right.index;
      }

      if (leftOrder === undefined) {
        return 1;
      }

      if (rightOrder === undefined) {
        return -1;
      }

      return leftOrder - rightOrder || left.index - right.index;
    })
    .map(item => item.entry);
}

function getParentAppDirectory(appPath) {
  const normalized = String(appPath || '').replace(/\\/g, '/');

  if (!normalized.endsWith('.app')) {
    return null;
  }

  const parentPath = normalized.substring(0, normalized.lastIndexOf('/'));

  if (!parentPath || parentPath === '/') {
    return null;
  }

  if (parentPath.endsWith('/Applications') || parentPath.endsWith('/System/Applications')) {
    return null;
  }

  return parentPath;
}

function buildFolderEntries(apps) {
  const regularApps = [];
  const folderMap = new Map();

  for (const app of apps) {
    const folderPath = getParentAppDirectory(app && app.path ? app.path : '');

    if (!folderPath) {
      regularApps.push(app);
      continue;
    }

    if (!folderMap.has(folderPath)) {
      folderMap.set(folderPath, []);
    }

    folderMap.get(folderPath).push(app);
  }

  const folderEntries = [];

  for (const [folderPath, folderApps] of folderMap.entries()) {
    if (folderApps.length <= 1) {
      regularApps.push(...folderApps);
      continue;
    }

    const folderName = folderPath.split('/').filter(Boolean).pop() || '文件夹';

    folderEntries.push({
      type: 'folder',
      name: folderName,
      path: folderPath,
      children: folderApps,
    });
  }

  return [...regularApps, ...folderEntries];
}

function applyManualAppGroups(entries, groups, apps, context) {
  let result = [...entries];

  for (const group of Array.isArray(groups) ? groups : []) {
    if (!group || group.context !== context || !Array.isArray(group.appPaths)) {
      continue;
    }

    const children = group.appPaths
      .map(appPath => apps.find(app => app && app.path === appPath))
      .filter(Boolean);

    if (children.length < 2) {
      continue;
    }

    const memberPaths = new Set(children.map(child => child.path));
    const replacedEntries = [];
    const representedPaths = new Set();

    for (const entry of result) {
      if (memberPaths.has(entry.path)) {
        replacedEntries.push(entry);
        representedPaths.add(entry.path);
        continue;
      }

      if (
        entry.type === 'folder' &&
        Array.isArray(entry.children) &&
        entry.children.length &&
        entry.children.every(child => memberPaths.has(child.path))
      ) {
        replacedEntries.push(entry);
        for (const child of entry.children) {
          representedPaths.add(child.path);
        }
      }
    }

    if (!children.every(child => representedPaths.has(child.path))) {
      continue;
    }

    const replacedSet = new Set(replacedEntries);
    result = result.filter(entry => !replacedSet.has(entry));
    result.push({
      type: 'folder',
      manualGroupId: group.id,
      name: group.name,
      path: `manual-folder:${group.id}`,
      children,
    });
  }

  return result;
}

function matchesEntry(entry, normalized) {
  if (!normalized) {
    return true;
  }

  const name = String(entry && entry.name ? entry.name : '');
  const path = String(entry && entry.path ? entry.path : '');

  if (name.toLowerCase().includes(normalized) || path.toLowerCase().includes(normalized)) {
    return true;
  }

  if (entry && entry.type === 'folder' && Array.isArray(entry.children)) {
    return entry.children.some(child => matchesEntry(child, normalized));
  }

  return false;
}

function filterApps(apps, query) {
  const normalized = normalizeQuery(query);

  if (!normalized) {
    return buildFolderEntries(apps);
  }

  return buildFolderEntries(apps).filter(entry => matchesEntry(entry, normalized));
}

function getAppLetter(app) {
  const name = String(app && app.name ? app.name : '').trim();

  if (!name) {
    return '#';
  }

  const first = name.charAt(0);

  if (/^[A-Za-z]$/.test(first)) {
    return first.toUpperCase();
  }

  return '#';
}

function groupAppsByLetter(apps) {
  const groups = new Map();

  for (const app of sortAppsByName(apps)) {
    const label = getAppLetter(app);

    if (!groups.has(label)) {
      groups.set(label, []);
    }

    groups.get(label).push(app);
  }

  return Array.from(groups.entries())
    .sort(([left], [right]) => {
      const leftIsNumber = /^\d$/.test(left);
      const rightIsNumber = /^\d$/.test(right);

      if (leftIsNumber && !rightIsNumber) {
        return -1;
      }

      if (!leftIsNumber && rightIsNumber) {
        return 1;
      }

      if (left === '#') {
        return -1;
      }

      if (right === '#') {
        return 1;
      }

      return left.localeCompare(right);
    })
    .map(([label, groupedApps]) => ({
      label,
      apps: groupedApps,
    }));
}

if (typeof window !== 'undefined') {
  window.normalizeQuery = normalizeQuery;
  window.filterApps = filterApps;
  window.sortAppsByName = sortAppsByName;
  window.sortEntriesByOrder = sortEntriesByOrder;
  window.getAppLetter = getAppLetter;
  window.groupAppsByLetter = groupAppsByLetter;
  window.getParentAppDirectory = getParentAppDirectory;
  window.buildFolderEntries = buildFolderEntries;
  window.applyManualAppGroups = applyManualAppGroups;
}

if (typeof module !== 'undefined') {
  module.exports = {
    normalizeQuery,
    filterApps,
    sortAppsByName,
    sortEntriesByOrder,
    getAppLetter,
    groupAppsByLetter,
    getParentAppDirectory,
    buildFolderEntries,
    applyManualAppGroups,
  };
}
