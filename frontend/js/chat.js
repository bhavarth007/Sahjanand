;(function() {
'use strict';
const CHAT_API = (typeof window.API !== 'undefined') ? window.API : (window.location.hostname === 'localhost' ? 'http://localhost:8000' : '');

// ── State ────────────────────────────────────────────────────────
let chatWs = null, chatInitialized = false, chatEventsBound = false;
let allUsers = [], groups = [], currentGroupId = null, groupMembers = [];
let chatOnline = new Set(), chatCanSend = true;
let currentUserId = null, currentIsAdmin = false;
let canManageGroups = false;
let typingTimer = null, isTyping = false;
let mentionActive = false, mentionQuery = '';
let oldestMsgId = null, isRecording = false, mediaRecorder = null, audioChunks = [];
let els = {};

function chatGetEls() {
  els = {
    groupList:    document.getElementById('chatGroupList'),
    groupTitle:   document.getElementById('chatGroupTitle'),
    messages:     document.getElementById('chatMessages'),
    textarea:     document.getElementById('chatTextarea'),
    sendBtn:      document.getElementById('chatSendBtn'),
    recordBtn:    document.getElementById('chatRecordBtn'),
    imageInput:   document.getElementById('chatImageInput'),
    videoInput:   document.getElementById('chatVideoInput'),
    mentionPopup: document.getElementById('chatMentionPopup'),
    userList:     document.getElementById('chatUserList'),
    userSearch:   document.getElementById('chatUserSearch'),
    typingBar:    document.getElementById('chatTypingBar'),
    onlineCount:  document.getElementById('chatOnlineCount'),
    inputBar:     document.getElementById('chatInputBar'),
    mutedBar:     document.getElementById('chatMutedBar'),
    loadMore:     document.getElementById('chatLoadMore'),
    lightbox:     document.getElementById('chatLightbox'),
    lightboxImg:  document.getElementById('chatLightboxImg'),
    groupInfoPanel: document.getElementById('chatGroupInfoPanel'),
    createGroupBtn: document.getElementById('chatCreateGroupBtn'),
  };
}

// ═══════════════════════════════════════════════════════════════
// Init
// ═══════════════════════════════════════════════════════════════
async function initChat() {
  const token = localStorage.getItem('sahjanand_token');
  const userData = JSON.parse(localStorage.getItem('sahjanand_user') || '{}');
  if (!token) return;
  currentUserId = userData.id;
  currentIsAdmin = userData.is_admin || false;
  const isSalesManager = (userData.designation || '').trim().toLowerCase() === 'sales manager';
  canManageGroups = currentIsAdmin || isSalesManager;

  chatGetEls();
  if (!chatEventsBound) { bindChatEvents(); chatEventsBound = true; }

  if (!chatInitialized) {
    chatInitialized = true;
    await Promise.all([loadAllUsers(token), loadGroups(token)]);
    if (canManageGroups && els.createGroupBtn) els.createGroupBtn.style.display = '';
    if (canManageGroups) { const del=document.getElementById('chatDeleteGroupBtn'); if(del) del.style.display=''; }
  }
}

// ═══════════════════════════════════════════════════════════════
// Load all users (left panel)
// ═══════════════════════════════════════════════════════════════
async function loadAllUsers(token) {
  try {
    const res = await fetch(`${CHAT_API}/api/chat/all-users`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return;
    allUsers = await res.json();
    renderUserList();
  } catch(e) { console.warn('[chat] users failed', e); }
}

function renderUserList(filter) {
  if (!els.userList) return;
  const lower = (filter || '').toLowerCase();
  const visible = allUsers.filter(u => !lower || (u.full_name || u.email).toLowerCase().includes(lower));
  els.userList.innerHTML = visible.map(u => {
    const name = u.full_name || u.email;
    const online = chatOnline.has(u.id) ? 'online' : '';
    const role = u.designation || (u.is_admin ? 'Admin' : 'Member');
    const mobile = u.mobile_no ? `<div style="font-size:.73rem;color:var(--text-secondary);margin-top:2px;"><i class="fa-solid fa-phone" style="width:14px;font-size:.65rem;color:var(--primary);"></i> ${esc(u.mobile_no)}</div>` : '';
    const emailRow = `<div style="font-size:.73rem;color:var(--text-secondary);margin-top:2px;"><i class="fa-solid fa-envelope" style="width:14px;font-size:.65rem;color:var(--primary);"></i> ${esc(u.email)}</div>`;
    const desigRow = u.designation ? `<div style="font-size:.73rem;color:var(--text-secondary);margin-top:2px;"><i class="fa-solid fa-briefcase" style="width:14px;font-size:.65rem;color:var(--primary);"></i> ${esc(u.designation)}</div>` : '';
    return `<div class="chat-member-item" onclick="toggleUserInfo(this)" style="flex-wrap:wrap;cursor:pointer;">
      <div class="chat-member-avatar ${online}">${chatInit(name)}</div>
      <div class="chat-member-info">
        <div class="chat-member-name">${esc(name)}</div>
        <div class="chat-member-role">${esc(role)}</div>
      </div>
      <div class="chat-user-detail" style="display:none;width:100%;padding:8px 12px 6px;margin-top:6px;background:#f9f5f3;border-radius:8px;border:1px solid var(--border);">
        ${desigRow}${mobile}${emailRow}
      </div>
    </div>`;
  }).join('');
}

// ═══════════════════════════════════════════════════════════════
// Load groups
// ═══════════════════════════════════════════════════════════════
async function loadGroups(token) {
  try {
    const res = await fetch(`${CHAT_API}/api/chat/groups`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return;
    groups = await res.json();
    renderGroupList();
    // Auto-select first group
    if (groups.length && !currentGroupId) {
      selectGroup(groups[0].id);
    }
  } catch(e) { console.warn('[chat] groups failed', e); }
}

function renderGroupList() {
  if (!els.groupList) return;
  els.groupList.innerHTML = groups.map(g => `
    <div class="chat-group-item ${g.id === currentGroupId ? 'active' : ''}"
         onclick="selectGroup(${g.id})">
      <div class="chat-group-avatar"><i class="fa-solid fa-users"></i></div>
      <div class="chat-group-info">
        <div class="chat-group-name">${esc(g.name)}</div>
      </div>
    </div>`).join('');
}

// ═══════════════════════════════════════════════════════════════
// Select / switch group
// ═══════════════════════════════════════════════════════════════
async function selectGroup(gid) {
  if (currentGroupId === gid && chatWs && chatWs.readyState === 1) return;
  currentGroupId = gid;
  window.currentGroupId = gid;
  const token = localStorage.getItem('sahjanand_token');

  // Update UI
  const group = groups.find(g => g.id === gid);
  if (els.groupTitle) els.groupTitle.textContent = group ? group.name : 'Group Chat';
  renderGroupList();

  // Close old WS
  if (chatWs && chatWs.readyState < 2) chatWs.close();
  chatWs = null;

  // Clear messages
  if (els.messages) els.messages.innerHTML = '';
  oldestMsgId = null;

  // Load members + messages + connect WS
  await Promise.all([loadGroupMembers(token, gid), loadMessages(token, gid)]);
  toggleInputBar();
  connectWs(token, gid);

  // Hide group info if open
  if (els.groupInfoPanel) els.groupInfoPanel.style.display = 'none';

  // Load group reminders
  window.currentGroupId = gid;
  if (typeof loadGroupReminders === 'function') loadGroupReminders('pending');
  if (typeof initFilters === 'function') initFilters();
}

async function loadGroupMembers(token, gid) {
  try {
    const res = await fetch(`${CHAT_API}/api/chat/groups/${gid}/members`, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) { groupMembers = []; return; }
    groupMembers = await res.json();
    const me = groupMembers.find(u => u.id === currentUserId);
    if (me) chatCanSend = me.chat_can_send;
  } catch { groupMembers = []; }
}

// ═══════════════════════════════════════════════════════════════
// Messages
// ═══════════════════════════════════════════════════════════════
let _lastDate = '';
async function loadMessages(token, gid, beforeId) {
  try {
    let url = `${CHAT_API}/api/chat/groups/${gid}/messages?limit=60`;
    if (beforeId) url += `&before_id=${beforeId}`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return;
    const msgs = await res.json();
    if (!msgs.length) { if (!beforeId) showEmpty(); if (els.loadMore) els.loadMore.style.display='none'; return; }
    oldestMsgId = msgs[0].id;
    if (els.loadMore) els.loadMore.style.display = msgs.length === 60 ? 'block' : 'none';
    _lastDate = '';
    if (beforeId) { msgs.forEach(m => prependMsg(m)); }
    else { hideEmpty(); msgs.forEach(m => appendMsg(m, false)); scrollBottom(); }
  } catch(e) { console.warn('[chat] messages failed', e); }
}

function buildBubble(msg) {
  const mine = msg.sender_id === currentUserId;
  const side = mine ? 'mine' : 'theirs';
  const name = msg.sender_name || 'Unknown';
  const time = fmtTime(msg.created_at);
  const date = fmtDate(msg.created_at);
  let divider = '';
  if (date !== _lastDate) { _lastDate = date; divider = `<div class="chat-date-divider"><span>${date}</span></div>`; }

  let body = '';
  switch (msg.msg_type) {
    case 'image': body = `<div class="chat-bubble-image"><img src="${esc(msg.media_url)}" onclick="openLightbox('${esc(msg.media_url)}')" loading="lazy"/></div>`; if(msg.content) body += `<div class="chat-bubble-text">${renderText(msg.content)}</div>`; break;
    case 'voice': body = `<div class="chat-bubble-voice"><i class="fa-solid fa-microphone chat-voice-icon"></i><audio controls src="${esc(msg.media_url)}" preload="none"></audio></div>`; break;
    case 'video': body = `<div class="chat-bubble-video"><video controls src="${esc(msg.media_url)}" preload="none"></video></div>`; break;
    default: body = `<div class="chat-bubble-text">${renderText(msg.content || '')}</div>`;
  }

  const deleteBtn = (mine || currentIsAdmin) ? `<button class="msg-delete-btn" onclick="deleteMessage(${msg.id})" title="Delete"><i class="fa-solid fa-trash-can"></i></button>` : '';

  return `${divider}<div class="chat-msg-row ${side}" data-msg-id="${msg.id}">
    <div class="chat-msg-sender-avatar">${chatInit(name)}</div>
    <div class="chat-bubble">
      ${mine ? '' : `<div class="chat-bubble-sender">${esc(name)}</div>`}
      ${body}
      <div class="chat-bubble-footer"><span class="chat-bubble-time">${time}</span>${deleteBtn}</div>
    </div></div>`;
}

function appendMsg(msg, scroll) { if(!els.messages) return; hideEmpty(); els.messages.insertAdjacentHTML('beforeend', buildBubble(msg)); if(scroll) scrollBottom(); }
function prependMsg(msg) { if(!els.messages) return; els.messages.insertAdjacentHTML('afterbegin', buildBubble(msg)); }
function scrollBottom() { if(els.messages) els.messages.scrollTop = els.messages.scrollHeight; }
function showEmpty() { if(els.messages && !els.messages.querySelector('.chat-empty')) els.messages.innerHTML = '<div class="chat-empty"><i class="fa-regular fa-comments"></i><p>No messages yet. Start the conversation!</p></div>'; }
function hideEmpty() { const e = els.messages && els.messages.querySelector('.chat-empty'); if(e) e.remove(); }

// ═══════════════════════════════════════════════════════════════
// Send messages
// ═══════════════════════════════════════════════════════════════
function sendText() {
  if (!chatCanSend || !els.textarea) return;
  const text = els.textarea.value.trim();
  if (!text) return;
  if (!currentGroupId) { toast('Select a group first','error'); return; }
  if (!chatWs || chatWs.readyState !== 1) {
    toast('Connecting… try again in a moment','error');
    connectWs(localStorage.getItem('sahjanand_token'), currentGroupId);
    return;
  }
  chatWs.send(JSON.stringify({ event:'message', msg_type:'text', content:text }));
  els.textarea.value = '';
  autoResize();
  closeMention();
}

async function sendMedia(file) {
  if (!chatCanSend) return;
  if (!currentGroupId) { toast('Select a group first','error'); return; }
  const token = localStorage.getItem('sahjanand_token');
  const fd = new FormData(); fd.append('file', file);
  toast('Uploading…','info');
  try {
    const res = await fetch(`${CHAT_API}/api/chat/upload`, { method:'POST', headers:{Authorization:`Bearer ${token}`}, body:fd });
    if (!res.ok) { const e = await res.json().catch(()=>({})); toast(e.detail||'Upload failed','error'); return; }
    const data = await res.json();
    if (chatWs && chatWs.readyState===1) chatWs.send(JSON.stringify({ event:'message', msg_type:data.msg_type, media_url:data.media_url, media_name:data.media_name, content:'' }));
    toast('Sent!','success');
  } catch { toast('Upload failed','error'); }
}

async function toggleRecord() {
  if (!chatCanSend) return;
  if (isRecording) { mediaRecorder && mediaRecorder.stop(); isRecording=false; els.recordBtn&&els.recordBtn.classList.remove('recording'); return; }
  try {
    const stream = await navigator.mediaDevices.getUserMedia({audio:true});
    audioChunks=[];
    mediaRecorder = new MediaRecorder(stream);
    mediaRecorder.ondataavailable = e => audioChunks.push(e.data);
    mediaRecorder.onstop = async () => { const blob=new Blob(audioChunks,{type:'audio/webm'}); const file=new File([blob],`voice_${Date.now()}.webm`,{type:'audio/webm'}); stream.getTracks().forEach(t=>t.stop()); await sendMedia(file); };
    mediaRecorder.start(); isRecording=true; els.recordBtn&&els.recordBtn.classList.add('recording');
  } catch { toast('Microphone denied','error'); }
}

// ═══════════════════════════════════════════════════════════════
// Delete message (self only)
// ═══════════════════════════════════════════════════════════════
async function deleteMessage(mid) {
  if (!confirm('Delete this message?')) return;
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${CHAT_API}/api/chat/messages/${mid}`, { method:'DELETE', headers:{Authorization:`Bearer ${token}`} });
    if (!res.ok) { const e=await res.json().catch(()=>({})); toast(e.detail||'Delete failed','error'); return; }
    // Remove from DOM
    const el = document.querySelector(`[data-msg-id="${mid}"]`);
    if (el) el.remove();
  } catch { toast('Network error','error'); }
}

// ═══════════════════════════════════════════════════════════════
// WebSocket
// ═══════════════════════════════════════════════════════════════
function connectWs(token, gid) {
  if (!gid || gid === 'null') return; // Don't connect without a valid group
  if (chatWs && chatWs.readyState < 2) chatWs.close();
  const proto = location.protocol==='https:'?'wss':'ws';
  const url = `${proto}://${location.host}/api/chat/ws?token=${encodeURIComponent(token)}&group_id=${gid}`;
  try { chatWs = new WebSocket(url); }
  catch(e) { console.warn('[chat] WS create failed', e); setTimeout(()=>connectWs(token,gid),3000); return; }

  chatWs.onopen = () => { console.log('[chat] WS open for group', gid); if(els.onlineCount) els.onlineCount.textContent='Connected'; };
  chatWs.onclose = (e) => { console.log('[chat] WS closed', e.code); chatWs=null; if(currentGroupId===gid) setTimeout(()=>connectWs(token,gid),3000); };
  chatWs.onerror = (e) => { console.warn('[chat] WS error', e); };
  chatWs.onmessage = evt => { try{handleWs(JSON.parse(evt.data));}catch(e){console.warn('[chat] parse err',e);} };
}

function handleWs(d) {
  switch(d.event) {
    case 'message': appendMsg(d,true); break;
    case 'message_deleted': const el=document.querySelector(`[data-msg-id="${d.id}"]`); if(el) el.remove(); break;
    case 'typing': showTyping(d); break;
    case 'user_joined': case 'user_left': chatOnline=new Set(d.online||[]); updateOnline(); break;
    case 'member_added': case 'member_removed': loadGroupMembers(localStorage.getItem('sahjanand_token'),currentGroupId); break;
    case 'error': toast(d.detail||'Error','error'); break;
  }
}

function updateOnline() { if(els.onlineCount) els.onlineCount.textContent=`${chatOnline.size} online`; renderUserList(els.userSearch?els.userSearch.value:''); }

// ═══════════════════════════════════════════════════════════════
// Typing
// ═══════════════════════════════════════════════════════════════
const _typing = new Map();
function sendTypingEvt(on) {
  if(!chatWs||chatWs.readyState!==1) return;
  if(on&&!isTyping){isTyping=true;chatWs.send(JSON.stringify({event:'typing',typing:true}));}
  clearTimeout(typingTimer);
  if(on) typingTimer=setTimeout(()=>{isTyping=false;if(chatWs&&chatWs.readyState===1)chatWs.send(JSON.stringify({event:'typing',typing:false}));},2000);
}
function showTyping(d) {
  if(d.user_id===currentUserId)return;
  if(d.typing)_typing.set(d.user_id,d.name);else _typing.delete(d.user_id);
  if(!els.typingBar)return;
  const n=[..._typing.values()];
  els.typingBar.textContent=!n.length?'':n.length===1?`${n[0]} is typing…`:`${n.slice(0,-1).join(', ')} and ${n.at(-1)} are typing…`;
}

// ═══════════════════════════════════════════════════════════════
// @mention
// ═══════════════════════════════════════════════════════════════
function handleMention() {
  const v=els.textarea?els.textarea.value:'', c=els.textarea?els.textarea.selectionStart:0;
  const m=v.slice(0,c).match(/@(\w*)$/);
  if(m){mentionQuery=m[1].toLowerCase();mentionActive=true;renderMention();}else closeMention();
  sendTypingEvt(true);
}
function renderMention() {
  if(!els.mentionPopup)return;
  const r=groupMembers.filter(u=>(u.full_name||u.email).toLowerCase().includes(mentionQuery)).slice(0,8);
  if(!r.length){closeMention();return;}
  els.mentionPopup.innerHTML=r.map((u,i)=>`<div class="mention-item ${i===0?'active':''}" onclick="insertMention('${esc(u.full_name||u.email)}')"><div class="mention-item-avatar">${chatInit(u.full_name||u.email)}</div><span class="mention-item-name">${esc(u.full_name||u.email)}</span></div>`).join('');
  els.mentionPopup.style.display='block';
}
function insertMention(name){if(!els.textarea)return;const v=els.textarea.value,c=els.textarea.selectionStart;els.textarea.value=v.slice(0,c).replace(/@(\w*)$/,`@${name} `)+v.slice(c);els.textarea.focus();closeMention();}
function closeMention(){mentionActive=false;if(els.mentionPopup)els.mentionPopup.style.display='none';}
function mentionKey(e){if(!mentionActive)return;const items=els.mentionPopup?els.mentionPopup.querySelectorAll('.mention-item'):[];let idx=[...items].findIndex(i=>i.classList.contains('active'));if(e.key==='ArrowDown'){e.preventDefault();items[idx]?.classList.remove('active');items[Math.min(idx+1,items.length-1)]?.classList.add('active');}else if(e.key==='ArrowUp'){e.preventDefault();items[idx]?.classList.remove('active');items[Math.max(idx-1,0)]?.classList.add('active');}else if(e.key==='Enter'){e.preventDefault();const a=els.mentionPopup?.querySelector('.mention-item.active');if(a)a.click();}else if(e.key==='Escape')closeMention();}

// ═══════════════════════════════════════════════════════════════
// Group Info Panel (click header → members, add, rename, remove)
// ═══════════════════════════════════════════════════════════════
let groupInfoOpen = false;
function toggleGroupInfo() {
  groupInfoOpen=!groupInfoOpen;
  if(!els.groupInfoPanel)return;
  if(groupInfoOpen){renderGroupInfo();els.groupInfoPanel.style.display='flex';}
  else els.groupInfoPanel.style.display='none';
}

// Mobile: toggle chat members sidebar
function toggleChatMembersMobile() {
  const panel = document.querySelector('.chat-members');
  if (panel) panel.classList.toggle('mobile-open');
}
// Close on clicking outside
document.addEventListener('click', function(e) {
  if (window.innerWidth > 900) return;
  const panel = document.querySelector('.chat-members');
  const header = document.querySelector('.chat-header');
  if (panel && panel.classList.contains('mobile-open') && !panel.contains(e.target) && !header.contains(e.target)) {
    panel.classList.remove('mobile-open');
  }
});
// Attach to chat header click on mobile
document.addEventListener('DOMContentLoaded', function() {
  const header = document.querySelector('.chat-header');
  if (header) {
    header.addEventListener('click', function(e) {
      if (window.innerWidth <= 900) {
        toggleChatMembersMobile();
        e.stopPropagation();
      }
    });
  }
});

async function renderGroupInfo() {
  if(!els.groupInfoPanel||!currentGroupId)return;
  const token=localStorage.getItem('sahjanand_token');
  const group=groups.find(g=>g.id===currentGroupId);
  const gName=group?group.name:'Group';

  let renameHtml='';
  if(canManageGroups) renameHtml=`<div class="group-info-edit-name"><label>Group Name</label><div style="display:flex;gap:8px;"><input type="text" id="groupNameInput" value="${esc(gName)}" class="admin-form-group-input"/><button class="btn-primary" onclick="renameGroup()" style="padding:8px 14px;font-size:.82rem;"><i class="fa-solid fa-check"></i></button></div></div>`;

  const membersHtml=groupMembers.map(u=>{
    const name=u.full_name||u.email;
    const rmBtn=(canManageGroups&&u.id!==currentUserId)?`<button class="admin-action-btn delete" title="Remove" onclick="removeMember(${u.id},'${esc(name)}')"><i class="fa-solid fa-user-minus"></i></button>`:'';
    return `<div class="chat-member-item" style="padding-right:10px;"><div class="chat-member-avatar ${chatOnline.has(u.id)?'online':''}">${chatInit(name)}</div><div class="chat-member-info" style="flex:1;"><div class="chat-member-name">${esc(name)} ${u.is_admin?'<span class="admin-badge">Admin</span>':''}</div><div class="chat-member-role">${esc(u.email)}</div></div>${rmBtn}</div>`;
  }).join('');

  let addHtml='';
  if(canManageGroups) addHtml=`<div class="group-info-section"><h5><i class="fa-solid fa-user-plus"></i> Add Member</h5><div style="display:flex;gap:8px;"><select id="addMemberSelect" class="admin-form-group-input" style="flex:1;padding:9px 12px;"><option value="">Loading…</option></select><button class="btn-primary" onclick="addMemberToGroup()" style="padding:9px 14px;font-size:.82rem;white-space:nowrap;"><i class="fa-solid fa-plus"></i> Add</button></div></div>`;

  els.groupInfoPanel.innerHTML=`<div class="group-info-header"><h4><i class="fa-solid fa-circle-info" style="margin-right:6px;color:var(--primary)"></i>Group Info</h4><button class="chat-icon-btn" onclick="toggleGroupInfo()"><i class="fa-solid fa-xmark"></i></button></div><div class="group-info-body">${renameHtml}<div class="group-info-section"><h5><i class="fa-solid fa-users"></i> ${groupMembers.length} Members</h5><div class="group-info-member-list">${membersHtml}</div></div>${addHtml}</div>`;

  if(canManageGroups) loadAvailable(token);
}

async function loadAvailable(token) {
  const sel=document.getElementById('addMemberSelect'); if(!sel)return;
  try{
    const res=await fetch(`${CHAT_API}/api/chat/groups/${currentGroupId}/available`,{headers:{Authorization:`Bearer ${token}`}});
    if(!res.ok){sel.innerHTML='<option>Error</option>';return;}
    const users=await res.json();
    sel.innerHTML=users.length?'<option value="">-- Select user --</option>'+users.map(u=>`<option value="${u.id}">${esc(u.full_name||u.email)} (${esc(u.email)})</option>`).join(''):'<option value="">No users available</option>';
  }catch{sel.innerHTML='<option>Error</option>';}
}

async function addMemberToGroup() {
  const sel=document.getElementById('addMemberSelect'); if(!sel||!sel.value){toast('Select a user','error');return;}
  const token=localStorage.getItem('sahjanand_token');
  try{
    const res=await fetch(`${CHAT_API}/api/chat/groups/${currentGroupId}/members`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({user_id:parseInt(sel.value)})});
    if(!res.ok){const e=await res.json().catch(()=>({}));toast(e.detail||'Failed','error');return;}
    toast('Member added!','success');
    await loadGroupMembers(token,currentGroupId); renderGroupInfo();
  }catch{toast('Network error','error');}
}

async function removeMember(uid,name) {
  if(!confirm(`Remove ${name} from group?`))return;
  const token=localStorage.getItem('sahjanand_token');
  try{
    const res=await fetch(`${CHAT_API}/api/chat/groups/${currentGroupId}/members/${uid}`,{method:'DELETE',headers:{Authorization:`Bearer ${token}`}});
    if(!res.ok){const e=await res.json().catch(()=>({}));toast(e.detail||'Failed','error');return;}
    toast(`${name} removed`,'success');
    await loadGroupMembers(token,currentGroupId); renderGroupInfo();
  }catch{toast('Network error','error');}
}

async function renameGroup() {
  const input=document.getElementById('groupNameInput'); if(!input||!input.value.trim())return;
  const token=localStorage.getItem('sahjanand_token');
  try{
    const res=await fetch(`${CHAT_API}/api/chat/groups/${currentGroupId}`,{method:'PATCH',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({name:input.value.trim()})});
    if(!res.ok){toast('Rename failed','error');return;}
    const g=await res.json();
    const idx=groups.findIndex(x=>x.id===g.id);if(idx>=0)groups[idx]=g;
    if(els.groupTitle)els.groupTitle.textContent=g.name;
    renderGroupList(); toast('Group renamed','success');
  }catch{toast('Network error','error');}
}

// ═══════════════════════════════════════════════════════════════
// Create new group (admin) — Professional modal instead of prompt()
// ═══════════════════════════════════════════════════════════════
async function createGroup() {
  // Show themed modal
  const existing = document.getElementById('createGroupModal');
  if (existing) existing.remove();

  const modal = document.createElement('div');
  modal.id = 'createGroupModal';
  modal.className = 'admin-modal-overlay';
  modal.style.display = 'flex';
  modal.innerHTML = `
    <div class="admin-modal" style="max-width:400px;">
      <div class="admin-modal-header" style="background:linear-gradient(135deg, var(--primary), var(--primary-dark));color:#fff;padding:16px 20px;border-radius:12px 12px 0 0;">
        <h4 style="margin:0;color:#fff;font-size:1rem;"><i class="fa-solid fa-users" style="margin-right:8px;"></i>Create New Group</h4>
        <button class="chat-icon-btn" onclick="document.getElementById('createGroupModal').remove()" style="color:#fff;background:rgba(255,255,255,0.15);"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <div style="padding:20px;">
        <label style="font-size:.78rem;font-weight:700;color:var(--text-muted);text-transform:uppercase;letter-spacing:.4px;">Group Name</label>
        <input type="text" id="createGroupNameInput" placeholder="e.g. Sales Team, Marketing..." style="width:100%;margin-top:6px;padding:12px 14px;border:1.5px solid var(--border);border-radius:10px;font-size:.95rem;font-family:inherit;outline:none;" autofocus />
        <div style="display:flex;gap:10px;margin-top:16px;justify-content:flex-end;">
          <button onclick="document.getElementById('createGroupModal').remove()" style="padding:9px 18px;border:1.5px solid var(--border);border-radius:8px;background:#fff;font-size:.85rem;cursor:pointer;font-family:inherit;">Cancel</button>
          <button onclick="submitCreateGroup()" class="btn-primary" style="padding:9px 18px;">Create Group</button>
        </div>
      </div>
    </div>`;
  document.body.appendChild(modal);

  // Focus input
  setTimeout(() => document.getElementById('createGroupNameInput')?.focus(), 100);

  // Enter key
  document.getElementById('createGroupNameInput')?.addEventListener('keydown', (e) => {
    if (e.key === 'Enter') submitCreateGroup();
  });
}

async function submitCreateGroup() {
  const input = document.getElementById('createGroupNameInput');
  const name = (input?.value || '').trim();
  if (!name) { input?.focus(); return; }

  if(groups.find(g=>g.name.toLowerCase()===name.toLowerCase())){toast('A group with this name already exists','error');return;}
  const token=localStorage.getItem('sahjanand_token');
  try{
    const res=await fetch(`${CHAT_API}/api/chat/groups`,{method:'POST',headers:{Authorization:`Bearer ${token}`,'Content-Type':'application/json'},body:JSON.stringify({name:name})});
    if(!res.ok){const e=await res.json().catch(()=>({}));toast(e.detail||'Failed','error');return;}
    const g=await res.json();
    groups.push(g); renderGroupList(); selectGroup(g.id);
    toast('Group created!','success');
  }catch{toast('Network error','error');}
  document.getElementById('createGroupModal')?.remove();
}

// ═══════════════════════════════════════════════════════════════
// Delete group
// ═══════════════════════════════════════════════════════════════
function deleteGroupPrompt() {
  if (!groups.length) { toast('No groups to delete','error'); return; }

  const existing = document.getElementById('deleteGroupModal');
  if (existing) existing.remove();

  const groupOptions = groups.map(g => `<option value="${g.id}">${esc(g.name)}</option>`).join('');

  const modal = document.createElement('div');
  modal.id = 'deleteGroupModal';
  modal.className = 'admin-modal-overlay';
  modal.style.display = 'flex';
  modal.innerHTML = `
    <div class="admin-modal" style="max-width:400px;">
      <div class="admin-modal-header" style="background:#c0392b;color:#fff;padding:16px 20px;border-radius:12px 12px 0 0;">
        <h4 style="margin:0;color:#fff;font-size:1rem;"><i class="fa-solid fa-trash-can" style="margin-right:8px;"></i>Delete Group</h4>
        <button class="chat-icon-btn" onclick="document.getElementById('deleteGroupModal').remove()" style="color:#fff;background:rgba(255,255,255,0.15);"><i class="fa-solid fa-xmark"></i></button>
      </div>
      <div style="padding:20px;">
        <label style="font-size:.78rem;font-weight:700;color:var(--text-muted);text-transform:uppercase;letter-spacing:.4px;">Select Group to Delete</label>
        <select id="deleteGroupSelect" style="width:100%;margin-top:6px;padding:12px 14px;border:1.5px solid var(--border);border-radius:10px;font-size:.95rem;font-family:inherit;outline:none;">
          ${groupOptions}
        </select>
        <p style="margin-top:12px;font-size:.8rem;color:#c0392b;"><i class="fa-solid fa-triangle-exclamation"></i> This will permanently delete the group and all messages.</p>
        <div style="display:flex;gap:10px;margin-top:16px;justify-content:flex-end;">
          <button onclick="document.getElementById('deleteGroupModal').remove()" style="padding:9px 18px;border:1.5px solid var(--border);border-radius:8px;background:#fff;font-size:.85rem;cursor:pointer;font-family:inherit;">Cancel</button>
          <button onclick="confirmDeleteGroup()" style="padding:9px 18px;border:none;border-radius:8px;background:#c0392b;color:#fff;font-size:.85rem;cursor:pointer;font-family:inherit;font-weight:600;">Delete</button>
        </div>
      </div>
    </div>`;
  document.body.appendChild(modal);
}

function confirmDeleteGroup() {
  const select = document.getElementById('deleteGroupSelect');
  if (!select || !select.value) return;
  const gid = parseInt(select.value);
  document.getElementById('deleteGroupModal')?.remove();
  deleteGroup(gid);
}

async function deleteGroup(gid) {
  const token = localStorage.getItem('sahjanand_token');
  try {
    const res = await fetch(`${CHAT_API}/api/chat/groups/${gid}`, { method:'DELETE', headers:{Authorization:`Bearer ${token}`} });
    if (!res.ok) { const e=await res.json().catch(()=>({})); toast(e.detail||'Delete failed','error'); return; }
    toast('Group deleted','success');
    groups = groups.filter(g => g.id !== gid);
    if (currentGroupId === gid) { currentGroupId = null; if(els.messages) els.messages.innerHTML=''; if(els.groupTitle) els.groupTitle.textContent='Select a group'; if(chatWs&&chatWs.readyState<2)chatWs.close(); }
    renderGroupList();
    if (groups.length && !currentGroupId) selectGroup(groups[0].id);
  } catch { toast('Network error','error'); }
}

// ═══════════════════════════════════════════════════════════════
// Input bar, lightbox, misc
// ═══════════════════════════════════════════════════════════════
function toggleInputBar(){if(!els.inputBar||!els.mutedBar)return;if(chatCanSend){els.inputBar.style.display='flex';els.mutedBar.style.display='none';}else{els.inputBar.style.display='none';els.mutedBar.style.display='flex';}}
function autoResize(){if(!els.textarea)return;els.textarea.style.height='auto';els.textarea.style.height=Math.min(els.textarea.scrollHeight,140)+'px';}
function openLightbox(src){if(!els.lightbox||!els.lightboxImg)return;els.lightboxImg.src=src;els.lightbox.classList.add('open');}
function closeLightbox(){if(!els.lightbox)return;els.lightbox.classList.remove('open');els.lightboxImg.src='';}

// ═══════════════════════════════════════════════════════════════
// Event bindings
// ═══════════════════════════════════════════════════════════════
function bindChatEvents() {
  if(els.textarea){
    els.textarea.addEventListener('input',()=>{autoResize();handleMention();});
    els.textarea.addEventListener('keydown',e=>{if(e.key==='Enter'&&!e.shiftKey){e.preventDefault();if(mentionActive)mentionKey(e);else sendText();return;}mentionKey(e);});
  }
  if(els.sendBtn) els.sendBtn.addEventListener('click', sendText);
  if(els.recordBtn) els.recordBtn.addEventListener('click', toggleRecord);
  if(els.imageInput) els.imageInput.addEventListener('change',async()=>{const f=els.imageInput.files[0];if(f){await sendMedia(f);els.imageInput.value='';}});
  if(els.videoInput) els.videoInput.addEventListener('change',async()=>{const f=els.videoInput.files[0];if(f){await sendMedia(f);els.videoInput.value='';}});
  if(els.userSearch) els.userSearch.addEventListener('input',()=>renderUserList(els.userSearch.value));
  if(els.loadMore){const b=els.loadMore.querySelector('button');if(b)b.addEventListener('click',()=>{const t=localStorage.getItem('sahjanand_token');if(oldestMsgId)loadMessages(t,currentGroupId,oldestMsgId);});}
  if(els.createGroupBtn) els.createGroupBtn.addEventListener('click',createGroup);
  document.addEventListener('click',e=>{if(els.mentionPopup&&!els.mentionPopup.contains(e.target)&&e.target!==els.textarea)closeMention();});
  if(els.lightbox) els.lightbox.addEventListener('click',e=>{if(e.target===els.lightbox)closeLightbox();});
}

// ═══════════════════════════════════════════════════════════════
// Helpers
// ═══════════════════════════════════════════════════════════════
function esc(s){if(!s)return '';return String(s).replace(/&/g,'&amp;').replace(/</g,'&lt;').replace(/>/g,'&gt;').replace(/"/g,'&quot;');}
function renderText(t){return esc(t).replace(/@(\w[\w\s]*?)(?=\s|$|[^a-zA-Z0-9_])/g,(_,n)=>`<span class="chat-mention">@${n}</span>`).replace(/\n/g,'<br>');}
function chatInit(n){const p=(n||'').trim().split(' ').filter(Boolean);if(p.length>=2)return(p[0][0]+p[1][0]).toUpperCase();return(n||'SJ').substring(0,2).toUpperCase();}
function fmtTime(iso){if(!iso)return'';const d=new Date(iso);if(isNaN(d.getTime())){const d2=new Date(iso+'Z');if(!isNaN(d2.getTime()))return d2.toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit',hour12:true,timeZone:'Asia/Kolkata'});return'';}return d.toLocaleTimeString('en-IN',{hour:'2-digit',minute:'2-digit',hour12:true,timeZone:'Asia/Kolkata'});}
function fmtDate(iso){if(!iso)return'';let d=new Date(iso);if(isNaN(d.getTime()))d=new Date(iso+'Z');if(isNaN(d.getTime()))return'';const now=new Date(),todayIST=new Date(now.toLocaleString('en-US',{timeZone:'Asia/Kolkata'})),dIST=new Date(d.toLocaleString('en-US',{timeZone:'Asia/Kolkata'})),diff=Math.floor((todayIST.setHours(0,0,0,0)-dIST.setHours(0,0,0,0))/86400000);if(diff===0)return'Today';if(diff===1)return'Yesterday';return d.toLocaleDateString('en-IN',{day:'numeric',month:'short',year:'numeric',timeZone:'Asia/Kolkata'});}
function toast(msg,type){const c={info:'#667781',success:'#25d366',error:'#c0392b'};const el=document.createElement('div');el.textContent=msg;Object.assign(el.style,{position:'fixed',bottom:'80px',left:'50%',transform:'translateX(-50%)',background:c[type]||'#667781',color:'#fff',padding:'8px 20px',borderRadius:'20px',fontSize:'.85rem',zIndex:'9998',boxShadow:'0 2px 10px rgba(0,0,0,.2)',fontFamily:'inherit',pointerEvents:'none'});document.body.appendChild(el);setTimeout(()=>el.remove(),2800);}

// ═══════════════════════════════════════════════════════════════
// Expose
// ═══════════════════════════════════════════════════════════════
window.initChat=initChat; window.selectGroup=selectGroup; window.toggleGroupInfo=toggleGroupInfo;
window.openLightbox=openLightbox; window.closeLightbox=closeLightbox;
window.insertMention=insertMention; window.deleteMessage=deleteMessage;
window.addMemberToGroup=addMemberToGroup; window.removeMember=removeMember;
// Expose refresh function for mobile app resume
window.refreshChatMessages = function() {
  const token = localStorage.getItem('sahjanand_token');
  if (token && currentGroupId) pollNewMessages();
};

// ═══════════════════════════════════════════════════════════════
// Live chat polling — fetch only NEW messages (no flicker)
// ═══════════════════════════════════════════════════════════════
let chatPollInterval = null;
let _latestMsgId = 0;

function startChatPolling() {
  if (chatPollInterval) return;
  chatPollInterval = setInterval(pollNewMessages, 4000);
}

async function pollNewMessages() {
  if (!currentGroupId) return;
  const token = localStorage.getItem('sahjanand_token');
  if (!token) return;
  try {
    let url = `${CHAT_API}/api/chat/groups/${currentGroupId}/messages?limit=20`;
    const res = await fetch(url, { headers: { Authorization: `Bearer ${token}` } });
    if (!res.ok) return;
    const msgs = await res.json();
    if (!msgs.length) return;

    // Find messages that are newer than what we already have
    const existingIds = new Set();
    document.querySelectorAll('[data-msg-id]').forEach(el => {
      existingIds.add(parseInt(el.dataset.msgId));
    });

    // Get the latest ID we have on screen
    let maxExisting = 0;
    existingIds.forEach(id => { if (id > maxExisting) maxExisting = id; });

    // Append only new messages
    let addedNew = false;
    msgs.forEach(m => {
      if (!existingIds.has(m.id) && m.id > maxExisting) {
        hideEmpty();
        appendMsg(m, false);
        addedNew = true;
      }
    });

    if (addedNew) scrollBottom();
  } catch(e) { /* silent */ }
}

// Start polling when chat initializes
setTimeout(startChatPolling, 3000);
window.renameGroup=renameGroup; window.createGroup=createGroup;
window.deleteGroupPrompt=deleteGroupPrompt; window.deleteGroup=deleteGroup;
window.submitCreateGroup=submitCreateGroup; window.confirmDeleteGroup=confirmDeleteGroup;
window.toggleUserInfo=function(el){
  const detail=el.querySelector('.chat-user-detail');
  if(!detail)return;
  // Close all others
  document.querySelectorAll('.chat-user-detail').forEach(d=>{if(d!==detail)d.style.display='none';});
  detail.style.display=detail.style.display==='none'?'block':'none';
};
})();
