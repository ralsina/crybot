class CrybotWeb {
  constructor() {
    this.ws = null;
    this.sessionId = null;
    this.currentSection = localStorage.getItem('crybotSection') || 'chat';
    this.currentTab = localStorage.getItem('crybotTab') || 'chat-tab';
    this.currentTelegramChat = null;
    this.pushToTalkActive = false;
    this.chatViewVisible = localStorage.getItem('crybotChatViewVisible') === 'true';
    this.configEditor = null;
    this.docsEditor = null;
    this.mcpServers = [];
    this.editingMCPServer = null;
    this.scheduledTasks = [];
    this.editingTaskId = null;

    this.init();
  }

  init() {
    this.setupNavigation();
    this.setupTabs();
    this.setupForms();
    this.setupSkillsHandlers();
    this.connectWebSocket();
    this.loadConfiguration();
    this.loadLogs();

    // Restore the saved section and tab
    this.showSection(this.currentSection);
    this.showTab(this.currentTab);
  }

  setupNavigation() {
    const navItems = document.querySelectorAll('.nav-item');
    navItems.forEach(item => {
      item.addEventListener('click', (e) => {
        e.preventDefault();
        const section = item.dataset.section;
        this.showSection(section);
      });
    });
  }

  showSection(section) {
    // Update nav items
    document.querySelectorAll('.nav-item').forEach(item => {
      item.classList.remove('active');
      if (item.dataset.section === section) {
        item.classList.add('active');
      }
    });

    // Update sections
    document.querySelectorAll('.section').forEach(sec => {
      sec.classList.remove('active');
    });
    document.getElementById(`section-${section}`).classList.add('active');

    this.currentSection = section;

    // Save to localStorage
    localStorage.setItem('crybotSection', section);

    // Load skills when navigating to skills section
    if (section === 'skills') {
      this.loadSkills();
    }

    // Load MCP servers when navigating to MCP section
    if (section === 'mcp') {
      this.loadMCPServers();
    }

    // Load scheduled tasks when navigating to scheduled tasks section
    if (section === 'scheduled-tasks') {
      this.loadScheduledTasks();
    }
  }

  setupTabs() {
    const tabs = document.querySelectorAll('.tab');
    tabs.forEach(tab => {
      tab.addEventListener('click', () => {
        const tabId = tab.dataset.tab;
        this.showTab(tabId);
      });
    });
  }

  showTab(tabId) {
    // Update tab buttons
    document.querySelectorAll('.tab').forEach(tab => {
      tab.classList.remove('active');
      if (tab.dataset.tab === tabId) {
        tab.classList.add('active');
      }
    });

    // Update tab content
    document.querySelectorAll('.tab-content').forEach(content => {
      content.classList.remove('active');
    });
    document.getElementById(tabId).classList.add('active');

    this.currentTab = tabId;

    // Save to localStorage
    localStorage.setItem('crybotTab', tabId);

    // Load content based on tab
    if (tabId === 'telegram-tab') {
      this.loadTelegramConversations();
    } else if (tabId === 'voice-tab') {
      this.loadVoiceConversation();
    }
  }

  setupForms() {
    // Chat form
    document.getElementById('chat-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendChatMessage('chat');
    });

    // Telegram form
    document.getElementById('telegram-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendChatMessage('telegram');
    });

    // Voice form
    document.getElementById('voice-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendChatMessage('voice');
    });

    // Config form
    document.getElementById('config-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.saveConfiguration();
    });

    // Telegram back button
    document.getElementById('telegram-back').addEventListener('click', () => {
      this.showTelegramList();
    });

    // Chat back button
    const chatBackBtn = document.getElementById('chat-back');
    if (chatBackBtn) {
      chatBackBtn.addEventListener('click', () => {
        this.showChatList();
      });
    }

    // New chat button
    const newChatBtn = document.getElementById('new-chat-btn');
    if (newChatBtn) {
      newChatBtn.addEventListener('click', () => {
        this.createNewChat();
      });
    }

    // Push-to-talk button
    const pttBtn = document.querySelector('.push-to-talk-btn');
    if (pttBtn) {
      // Mouse events
      pttBtn.addEventListener('mousedown', (e) => {
        e.preventDefault();
        this.activatePushToTalk();
      });
      pttBtn.addEventListener('mouseup', () => {
        this.deactivatePushToTalk();
      });
      pttBtn.addEventListener('mouseleave', () => {
        if (this.pushToTalkActive) {
          this.deactivatePushToTalk();
        }
      });

      // Touch events for mobile
      pttBtn.addEventListener('touchstart', (e) => {
        e.preventDefault();
        this.activatePushToTalk();
      });
      pttBtn.addEventListener('touchend', (e) => {
        e.preventDefault();
        this.deactivatePushToTalk();
      });
    }
  }

  setupSkillsHandlers() {
    // Add skill button
    document.getElementById('add-skill-btn').addEventListener('click', () => {
      this.openCreateSkillModal();
    });

    // Reload skills button
    document.getElementById('reload-skills-btn').addEventListener('click', () => {
      this.reloadSkills();
    });

    // Skill back button
    document.getElementById('skill-back-btn').addEventListener('click', () => {
      this.closeSkillEditor();
    });

    // Save skill button
    document.getElementById('save-skill-btn').addEventListener('click', () => {
      this.saveSkill();
    });

    // Save docs button
    document.getElementById('save-docs-btn').addEventListener('click', () => {
      this.saveSkill();
    });

    // Save credentials button
    document.getElementById('save-credentials-btn').addEventListener('click', () => {
      this.saveCredentials();
    });

    // Create skill modal
    document.getElementById('create-skill-confirm-btn').addEventListener('click', () => {
      this.createSkill();
    });

    document.getElementById('cancel-create-btn').addEventListener('click', () => {
      this.closeCreateSkillModal();
    });

    document.getElementById('close-modal-btn').addEventListener('click', () => {
      this.closeCreateSkillModal();
    });

    // MCP handlers
    const addMcpBtn = document.getElementById('add-mcp-server-btn');
    if (addMcpBtn) {
      addMcpBtn.addEventListener('click', () => {
        this.openAddMCPServerModal();
      });
    } else {
      console.error('add-mcp-server-btn not found');
    }

    // MCP modal handlers
    document.getElementById('close-mcp-modal-btn').addEventListener('click', () => {
      this.closeMCPServerModal();
    });

    document.getElementById('cancel-mcp-btn').addEventListener('click', () => {
      this.closeMCPServerModal();
    });

    document.getElementById('save-mcp-btn').addEventListener('click', () => {
      this.saveMCPServerFromModal();
    });

    // Connection type change handler
    document.getElementById('mcp-connection-type').addEventListener('change', (e) => {
      this.toggleMCPConnectionType(e.target.value);
    });

    // Scheduled tasks handlers
    const addTaskBtn = document.getElementById('add-task-btn');
    if (addTaskBtn) {
      addTaskBtn.addEventListener('click', () => {
        this.openTaskModal();
      });
    }

    const reloadTasksBtn = document.getElementById('reload-tasks-btn');
    if (reloadTasksBtn) {
      reloadTasksBtn.addEventListener('click', () => {
        this.reloadScheduledTasks();
      });
    }

    // Task modal handlers
    document.getElementById('close-task-modal-btn').addEventListener('click', () => {
      this.closeTaskModal();
    });

    document.getElementById('cancel-task-btn').addEventListener('click', () => {
      this.closeTaskModal();
    });

    document.getElementById('save-task-btn').addEventListener('click', () => {
      this.saveTask();
    });

    // Task output modal handlers
    document.getElementById('close-task-output-modal-btn').addEventListener('click', () => {
      this.closeTaskOutputModal();
    });

    // Task output form
    document.getElementById('task-output-form').addEventListener('submit', (e) => {
      e.preventDefault();
      this.sendTaskOutputMessage();
    });

    // Load telegram chats button
    const loadTelegramChatsBtn = document.getElementById('load-telegram-chats-btn');
    if (loadTelegramChatsBtn) {
      loadTelegramChatsBtn.addEventListener('click', () => {
        this.loadTelegramChatsForForwarding();
      });
    }

    // Unified channel selection for forwarding
    const channelSelect = document.getElementById('task-forward-channel');
    const loadChatsBtn = document.getElementById('load-chats-btn');
    const forwardToInput = document.getElementById('task-forward-to');

    if (channelSelect && loadChatsBtn && forwardToInput) {
      channelSelect.addEventListener('change', (e) => {
        const channel = e.target.value;
        loadChatsBtn.disabled = !channel;

        if (channel === 'telegram') {
          loadChatsBtn.textContent = '📋 Load Chats';
          forwardToInput.placeholder = 'Click "Load Chats" to select a Telegram chat';
        } else if (channel === 'web') {
          loadChatsBtn.textContent = '📋 Load Sessions';
          forwardToInput.placeholder = 'Enter a web session ID';
        } else if (channel === 'voice' || channel === 'repl') {
          loadChatsBtn.disabled = true;
          forwardToInput.value = channel + ':';
          forwardToInput.placeholder = 'Uses shared session (no ID needed)';
        } else {
          loadChatsBtn.disabled = true;
          forwardToInput.placeholder = 'Select a channel first';
        }
      });

      loadChatsBtn.addEventListener('click', () => {
        const channel = channelSelect.value;
        if (channel === 'telegram') {
          this.loadTelegramChatsForForwarding();
        } else if (channel === 'web') {
          this.loadWebSessionsForForwarding();
        }
      });
    }
  }

  openAddMCPServerModal() {
    this.editingMCPServer = null;
    document.getElementById('mcp-modal-title').textContent = 'Add MCP Server';
    document.getElementById('mcp-server-name').value = '';
    document.getElementById('mcp-server-name').disabled = false;
    document.getElementById('mcp-connection-type').value = 'command';
    document.getElementById('mcp-command').value = '';
    document.getElementById('mcp-url').value = '';
    this.toggleMCPConnectionType('command');

    document.getElementById('mcp-server-modal').classList.remove('hidden');
  }

  editMCPServer(serverName) {
    const server = this.mcpServers.find(s => s.name === serverName);
    if (!server) return;

    this.editingMCPServer = serverName;
    document.getElementById('mcp-modal-title').textContent = 'Edit MCP Server';
    document.getElementById('mcp-server-name').value = serverName;
    document.getElementById('mcp-server-name').disabled = true;

    if (server.command) {
      document.getElementById('mcp-connection-type').value = 'command';
      document.getElementById('mcp-command').value = server.command;
      this.toggleMCPConnectionType('command');
    } else if (server.url) {
      document.getElementById('mcp-connection-type').value = 'http';
      document.getElementById('mcp-url').value = server.url;
      this.toggleMCPConnectionType('http');
    }

    document.getElementById('mcp-server-modal').classList.remove('hidden');
  }

  closeMCPServerModal() {
    document.getElementById('mcp-server-modal').classList.add('hidden');
    this.editingMCPServer = null;
  }

  toggleMCPConnectionType(type) {
    const commandGroup = document.getElementById('mcp-command-group');
    const urlGroup = document.getElementById('mcp-url-group');

    if (type === 'command') {
      commandGroup.classList.remove('hidden');
      urlGroup.classList.add('hidden');
    } else {
      commandGroup.classList.add('hidden');
      urlGroup.classList.remove('hidden');
    }
  }

  async saveMCPServerFromModal() {
    const name = document.getElementById('mcp-server-name').value.trim();
    const connectionType = document.getElementById('mcp-connection-type').value;
    const command = document.getElementById('mcp-command').value.trim();
    const url = document.getElementById('mcp-url').value.trim();

    if (!name) {
      alert('Please enter a server name');
      return;
    }

    if (connectionType === 'command' && !command) {
      alert('Please enter a command');
      return;
    }

    if (connectionType === 'http' && !url) {
      alert('Please enter a URL');
      return;
    }

    this.mcpServers = this.mcpServers || [];

    if (this.editingMCPServer) {
      // Update existing server
      const index = this.mcpServers.findIndex(s => s.name === this.editingMCPServer);
      if (index !== -1) {
        this.mcpServers[index] = {
          name,
          command: connectionType === 'command' ? command : null,
          url: connectionType === 'http' ? url : null,
        };
      }
    } else {
      // Add new server
      if (this.mcpServers.some(s => s.name === name)) {
        alert('A server with this name already exists');
        return;
      }
      this.mcpServers.push({
        name,
        command: connectionType === 'command' ? command : null,
        url: connectionType === 'http' ? url : null,
      });
    }

    await this.saveMCPServers();
    this.closeMCPServerModal();
  }

  loadMCPServers() {
    const container = document.getElementById('mcp-servers-list');

    if (!this.mcpServers || this.mcpServers.length === 0) {
      container.innerHTML = '<p class="empty-state">No MCP servers configured.</p>';
      return;
    }

    container.innerHTML = '';
    this.mcpServers.forEach(server => {
      const card = document.createElement('div');
      card.className = 'mcp-server-card';
      card.innerHTML = `
        <div class="mcp-server-header">
          <span class="mcp-server-name">${this.escapeHtml(server.name)}</span>
          <div class="mcp-server-actions">
            <button class="btn-sm btn-secondary" onclick="app.editMCPServer('${this.escapeHtml(server.name)}')">Edit</button>
            <button class="btn-sm btn-delete" onclick="app.deleteMCPServer('${this.escapeHtml(server.name)}')">Delete</button>
          </div>
        </div>
        <div class="mcp-server-details">
          ${server.command ? `<div><strong>Command:</strong> <code>${this.escapeHtml(server.command)}</code></div>` : ''}
          ${server.url ? `<div><strong>URL:</strong> <code>${this.escapeHtml(server.url)}</code></div>` : ''}
        </div>
      `;
      container.appendChild(card);
    });
  }

  async deleteMCPServer(serverName) {
    if (!confirm(`Delete MCP server "${serverName}"?`)) return;

    this.mcpServers = this.mcpServers.filter(s => s.name !== serverName);
    await this.saveMCPServers();
  }

  async saveMCPServers() {
    try {
      const response = await fetch('/api/config', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          mcp: {
            servers: this.mcpServers
          }
        }),
      });

      const data = await response.json();

      if (data.success) {
        // Reload MCP servers - but expect this might fail if crybot restarts
        try {
          await fetch('/api/agent/reload-mcp', { method: 'POST', signal: AbortSignal.timeout(5000) });
        } catch (reloadError) {
          // Ignore reload errors - likely due to config watcher restart
          console.log('MCP reload skipped (server may be restarting):', reloadError.message);
        }

        this.loadMCPServers();
        alert('MCP servers saved successfully! Crybot will reload the configuration.');
      } else {
        alert(`Failed to save: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to save MCP servers:', error);
      alert('Failed to save MCP servers: ' + error.message);
    }
  }

  connectWebSocket() {
    const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
    const wsUrl = `${protocol}//${window.location.host}/ws/chat`;

    this.ws = new WebSocket(wsUrl);

    this.ws.onopen = () => {
      console.log('Connected to Crybot');

      // Load sessions list first
      this.loadSessionsList();

      // Only request history if we were in chat view
      if (this.chatViewVisible) {
        const savedSessionId = localStorage.getItem('crybotChatSession') || null;
        if (savedSessionId) {
          this.ws.send(JSON.stringify({
            type: 'history_request',
            session_id: savedSessionId,
          }));
        } else {
          // No saved session, show list view
          this.showChatList();
        }
      } else {
        // Show list view
        this.showChatList();
      }
    };

    this.ws.onmessage = (event) => {
      const data = JSON.parse(event.data);
      this.handleWebSocketMessage(data);
    };

    this.ws.onclose = () => {
      console.log('Disconnected from Crybot');
      setTimeout(() => this.connectWebSocket(), 3000);
    };

    this.ws.onerror = (error) => {
      console.error('WebSocket error:', error);
    };
  }

  handleWebSocketMessage(data) {
    switch (data.type) {
      case 'connected':
        this.sessionId = data.session_id;
        // Save to localStorage if not already saved
        if (!localStorage.getItem('crybotChatSession')) {
          localStorage.setItem('crybotChatSession', data.session_id);
        }
        // Load sessions list after connecting
        this.loadSessionsList();
        break;
      case 'history':
        this.loadHistory(data.messages, data.session_id);
        // Show chat view when history is loaded
        this.showChatView();
        // Refresh sessions list to show all available
        this.loadSessionsList();
        break;
      case 'session_switched':
        this.sessionId = data.session_id;
        localStorage.setItem('crybotChatSession', data.session_id);
        // Clear the chat container and show it's a new session
        document.getElementById('chat-messages').innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">New conversation started</p>';
        // Show chat view
        this.showChatView();
        // Refresh sessions list
        this.loadSessionsList();
        break;
      case 'status':
        if (data.status === 'processing') {
          this.showTypingIndicator(this.getCurrentContainer());
        }
        break;
      case 'response':
        this.hideTypingIndicator(this.getCurrentContainer());
        this.addMessage(data.content, 'assistant', this.getCurrentContainer());
        break;
      case 'telegram_message':
        // New message arrived via Telegram
        this.handleExternalMessage('telegram', data);
        break;
      case 'voice_message':
        // New message arrived via Voice
        this.handleExternalMessage('voice', data);
        break;
      case 'error':
        this.hideTypingIndicator(this.getCurrentContainer());
        this.addMessage(`Error: ${data.message}`, 'system', this.getCurrentContainer());
        break;
    }
  }

  loadHistory(messages, sessionId) {
    this.sessionId = sessionId;
    localStorage.setItem('crybotChatSession', sessionId);

    const container = document.getElementById('chat-messages');
    container.innerHTML = '';

    if (!messages || messages.length === 0) {
      container.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No messages yet. Start a conversation!</p>';
      return;
    }

    messages.forEach((msg) => {
      if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
        this.addMessage(msg.content, msg.role, 'chat-messages');
      }
    });
  }

  showTypingIndicator(containerId) {
    const container = document.getElementById(containerId);
    if (!container) return;

    // Remove existing indicator if any
    this.hideTypingIndicator(containerId);

    const indicator = document.createElement('div');
    indicator.className = 'message assistant typing-indicator';
    indicator.id = `${containerId}-typing`;
    indicator.innerHTML = `
      <div class="message-avatar">C</div>
      <div class="message-content">
        <div class="typing-dots">
          <span></span>
          <span></span>
          <span></span>
        </div>
      </div>
    `;
    container.appendChild(indicator);
    container.scrollTop = container.scrollHeight;
  }

  hideTypingIndicator(containerId) {
    const indicator = document.getElementById(`${containerId}-typing`);
    if (indicator) {
      indicator.remove();
    }
  }

  handleExternalMessage(source, data) {
    console.log(`[${source.toUpperCase()}] Received external message:`, data);
    console.log(`Current tab: ${this.currentTab}`);

    // If we're currently viewing the corresponding tab, refresh the content
    if (this.currentTab === `${source}-tab`) {
      console.log('On matching tab, checking view state...');

      if (source === 'telegram') {
        // If we're viewing the conversation list, refresh it
        const listContainer = document.getElementById('telegram-list');
        const chatView = document.getElementById('telegram-chat-view');

        console.log('List container hidden?', listContainer?.classList.contains('hidden'));
        console.log('Chat view hidden?', chatView?.classList.contains('hidden'));
        console.log('Current telegram chat:', this.currentTelegramChat);

        if (listContainer && !listContainer.classList.contains('hidden')) {
          console.log('Refreshing telegram list...');
          this.loadTelegramConversations();
        } else if (chatView && !chatView.classList.contains('hidden') && this.currentTelegramChat) {
          console.log('Refreshing telegram chat:', this.currentTelegramChat);
          this.openTelegramChat(this.currentTelegramChat);
        } else {
          console.log('Not viewing a telegram list or chat');
        }
      } else if (source === 'voice') {
        // Reload voice conversation
        this.loadVoiceConversation();
      }
    } else {
      console.log(`Not on ${source} tab (on ${this.currentTab}), skipping refresh`);
    }
  }

  getCurrentContainer() {
    switch (this.currentTab) {
      case 'chat-tab':
        return 'chat-messages';
      case 'telegram-tab':
        return 'telegram-messages';
      case 'voice-tab':
        return 'voice-messages';
      default:
        return 'chat-messages';
    }
  }

  sendChatMessage(context) {
    const formId = context === 'chat' ? 'chat-form' :
                    context === 'telegram' ? 'telegram-form' : 'voice-form';
    const form = document.getElementById(formId);
    const input = form.querySelector('.message-input');
    const content = input.value.trim();

    if (!content) return;

    // For telegram, send to the telegram-specific endpoint
    if (context === 'telegram' && this.currentTelegramChat) {
      this.sendToTelegram(content);
      return;
    }

    this.addMessage(content, 'user', this.getCurrentContainer());
    input.value = '';

    // Send via WebSocket
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'message',
        session_id: this.sessionId || '',
        content: content,
      }));
    } else {
      // Fallback to REST API
      this.sendViaAPI(content);
    }
  }

  async sendToTelegram(content) {
    const form = document.getElementById('telegram-form');
    const input = form.querySelector('.message-input');

    this.addMessage(content, 'user', 'telegram-messages');
    input.value = '';

    // Show typing indicator
    this.showTypingIndicator('telegram-messages');

    try {
      const response = await fetch(`/api/telegram/conversations/${encodeURIComponent(this.currentTelegramChat)}/message`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ content }),
      });

      const data = await response.json();
      if (data.error) {
        this.hideTypingIndicator('telegram-messages');
        this.addMessage(`Error: ${data.error}`, 'system', 'telegram-messages');
      }
      // Note: We don't manually add the assistant message here because
      // the WebSocket broadcast will handle displaying the response
      // The broadcast will also hide the typing indicator
    } catch (error) {
      this.hideTypingIndicator('telegram-messages');
      console.error('Failed to send to telegram:', error);
      this.addMessage('Failed to send message to Telegram', 'system', 'telegram-messages');
    }
  }

  async sendViaAPI(content) {
    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: this.sessionId || '',
          content: content,
        }),
      });

      const data = await response.json();
      if (data.content) {
        this.addMessage(data.content, 'assistant', this.getCurrentContainer());
      }
    } catch (error) {
      this.addMessage('Failed to send message', 'system', this.getCurrentContainer());
    }
  }

  addMessage(content, role, containerId) {
    console.log('addMessage called:', { containerId, role, contentLength: content?.length });
    const container = document.getElementById(containerId);
    console.log('Container element:', container);
    if (!container) {
      console.error('Container not found:', containerId);
      return;
    }

    const messageEl = document.createElement('div');
    messageEl.className = `message ${role}`;

    const avatar = role === 'user' ? 'U' : role === 'assistant' ? 'C' : '!';
    const time = new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });

    // Parse markdown for assistant messages, escape HTML for user messages
    let renderedContent;
    if (role === 'assistant') {
      // Parse markdown for assistant messages
      renderedContent = typeof marked !== 'undefined' ? marked.parse(content) : this.escapeHtml(content);
    } else {
      renderedContent = this.escapeHtml(content);
    }

    messageEl.innerHTML = `
      <div class="message-avatar">${avatar}</div>
      <div class="message-content">
        <div class="message-bubble">${renderedContent}</div>
        <div class="message-time">${time}</div>
      </div>
    `;

    console.log('Appending message element to container');
    container.appendChild(messageEl);
    console.log('Message appended, container now has', container.children.length, 'children');
    container.scrollTop = container.scrollHeight;
  }

  async loadTelegramConversations() {
    const listContainer = document.getElementById('telegram-list');
    listContainer.innerHTML = '<p style="color: #666;">Loading conversations...</p>';

    try {
      const response = await fetch('/api/telegram/conversations');
      const data = await response.json();

      if (!data.conversations || data.conversations.length === 0) {
        listContainer.innerHTML = '<p style="color: #666;">No conversations found.</p>';
        return;
      }

      listContainer.innerHTML = '';
      data.conversations.forEach(conv => {
        const item = document.createElement('div');
        item.className = 'telegram-conversation-item';
        item.innerHTML = `
          <div class="telegram-conversation-title">${this.escapeHtml(conv.title || 'Unknown')}</div>
          <div class="telegram-conversation-preview">${this.escapeHtml(conv.preview || 'No messages')}</div>
          <div class="telegram-conversation-time">${conv.time || ''}</div>
        `;
        item.addEventListener('click', () => this.openTelegramChat(conv.id));
        listContainer.appendChild(item);
      });
    } catch (error) {
      listContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load conversations.</p>';
    }
  }

  async openTelegramChat(chatId) {
    console.log('openTelegramChat called with:', chatId);
    this.currentTelegramChat = chatId;

    const listContainer = document.getElementById('telegram-list');
    const chatView = document.getElementById('telegram-chat-view');

    console.log('Before toggle - list hidden?', listContainer?.classList.contains('hidden'));
    console.log('Before toggle - chatView hidden?', chatView?.classList.contains('hidden'));

    listContainer?.classList.add('hidden');
    chatView?.classList.remove('hidden');

    console.log('After toggle - list hidden?', listContainer?.classList.contains('hidden'));
    console.log('After toggle - chatView hidden?', chatView?.classList.contains('hidden'));

    // Load messages for this chat
    const messagesContainer = document.getElementById('telegram-messages');
    console.log('Messages container:', messagesContainer);
    console.log('Is container in DOM?', document.body.contains(messagesContainer));
    messagesContainer.innerHTML = '<p style="color: #666;">Loading messages...</p>';

    try {
      const url = `/api/telegram/conversations/${encodeURIComponent(chatId)}?_=${Date.now()}`;
      console.log('Fetching from:', url);
      const response = await fetch(url, { cache: 'no-store' });
      const data = await response.json();
      console.log('Response data:', data);

      messagesContainer.innerHTML = '';

      if (!data.messages || data.messages.length === 0) {
        console.log('No messages found in response');
        messagesContainer.innerHTML = '<p style="color: #666;">No messages yet.</p>';
        return;
      }

      console.log('Processing', data.messages.length, 'messages');
      // Display messages (filter out system messages)
      data.messages.forEach((msg, index) => {
        console.log(`Message ${index}:`, msg);
        // Only show user and assistant messages, skip system/tool messages
        if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
          console.log('Adding message with role:', msg.role);
          this.addMessage(msg.content, msg.role, 'telegram-messages');
        }
      });
      console.log('Finished adding messages, container children:', messagesContainer.children.length);

      // Force reflow and scroll to bottom
      messagesContainer.offsetHeight; // Force reflow
      messagesContainer.scrollTop = messagesContainer.scrollHeight;

      // Debug: check if messages are actually visible
      console.log('Container styles:', {
        display: getComputedStyle(messagesContainer).display,
        visibility: getComputedStyle(messagesContainer).visibility,
        height: getComputedStyle(messagesContainer).height,
        overflow: getComputedStyle(messagesContainer).overflow,
        clientHeight: messagesContainer.clientHeight,
        scrollHeight: messagesContainer.scrollHeight,
      });

      // Log first few message elements
      for (let i = 0; i < Math.min(3, messagesContainer.children.length); i++) {
        const child = messagesContainer.children[i];
        console.log(`Child ${i}:`, {
          tagName: child.tagName,
          className: child.className,
          display: getComputedStyle(child).display,
          offsetHeight: child.offsetHeight,
          innerHTML: child.innerHTML.substring(0, 100),
        });
      }
    } catch (error) {
      console.error('Failed to load messages:', error);
      messagesContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load messages.</p>';
    }
  }

  showTelegramList() {
    this.currentTelegramChat = null;
    document.getElementById('telegram-list').classList.remove('hidden');
    document.getElementById('telegram-chat-view').classList.add('hidden');
  }

  async loadVoiceConversation() {
    const messagesContainer = document.getElementById('voice-messages');
    messagesContainer.innerHTML = '<p style="color: #666;">Loading voice conversation...</p>';

    try {
      const response = await fetch('/api/voice/conversation/current');
      const data = await response.json();

      messagesContainer.innerHTML = '';

      if (!data.messages || data.messages.length === 0) {
        messagesContainer.innerHTML = '<p style="color: #666;">No voice conversations yet. Use voice mode to start chatting.</p>';
        return;
      }

      // Display messages (filter out system messages)
      data.messages.forEach(msg => {
        // Only show user and assistant messages, skip system/tool messages
        if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
          this.addMessage(msg.content, msg.role, 'voice-messages');
        }
      });
    } catch (error) {
      console.error('Failed to load voice conversation:', error);
      messagesContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load voice conversation.</p>';
    }
  }

  async loadConfiguration() {
    try {
      const response = await fetch('/api/config');
      const config = await response.json();

      // Web
      document.getElementById('web-enabled').checked = config.web?.enabled || false;
      document.getElementById('web-host').value = config.web?.host || '127.0.0.1';
      document.getElementById('web-port').value = config.web?.port || 3000;
      document.getElementById('web-auth-token').value = '';

      // Agents
      document.getElementById('agent-model').value = config.agents?.defaults?.model || 'glm-4.7-flash';
      document.getElementById('agent-temperature').value = config.agents?.defaults?.temperature || 0.7;
      document.getElementById('agent-max-tokens').value = config.agents?.defaults?.max_tokens || 4096;

      // Providers
      document.getElementById('provider-zhipu-key').value = '';
      document.getElementById('provider-openai-key').value = '';
      document.getElementById('provider-anthropic-key').value = '';

      // Channels - Telegram
      document.getElementById('telegram-enabled').checked = config.channels?.telegram?.enabled || false;
      document.getElementById('telegram-token').value = '';
      document.getElementById('telegram-allow-from').value = (config.channels?.telegram?.allow_from || []).join(', ');

      // Voice
      document.getElementById('voice-wake-word').value = config.voice?.wake_word || '';
      document.getElementById('voice-whisper-path').value = config.voice?.whisper_stream_path || '';
      document.getElementById('voice-model-path').value = config.voice?.model_path || '';
      document.getElementById('voice-language').value = config.voice?.language || 'en';
      document.getElementById('voice-threads').value = config.voice?.threads || 4;
      document.getElementById('voice-piper-model').value = config.voice?.piper_model || '';
      document.getElementById('voice-piper-path').value = config.voice?.piper_path || '';
      document.getElementById('voice-timeout').value = config.voice?.conversational_timeout || 3;

      // MCP - store for later use
      this.mcpServers = config.mcp?.servers || [];
      this.loadMCPServers();
    } catch (error) {
      console.error('Failed to load configuration:', error);
    }
  }

  async saveConfiguration() {
    const config = {
      web: {
        enabled: document.getElementById('web-enabled').checked,
        host: document.getElementById('web-host').value,
        port: parseInt(document.getElementById('web-port').value),
        auth_token: document.getElementById('web-auth-token').value,
      },
      agents: {
        defaults: {
          model: document.getElementById('agent-model').value,
          temperature: parseFloat(document.getElementById('agent-temperature').value),
          max_tokens: parseInt(document.getElementById('agent-max-tokens').value),
        },
      },
      providers: {
        zhipu: { api_key: document.getElementById('provider-zhipu-key').value },
        openai: { api_key: document.getElementById('provider-openai-key').value },
        anthropic: { api_key: document.getElementById('provider-anthropic-key').value },
      },
      channels: {
        telegram: {
          enabled: document.getElementById('telegram-enabled').checked,
          token: document.getElementById('telegram-token').value,
          allow_from: document.getElementById('telegram-allow-from').value.split(',').map(s => s.trim()).filter(s => s),
        },
      },
      voice: {
        wake_word: document.getElementById('voice-wake-word').value || undefined,
        whisper_stream_path: document.getElementById('voice-whisper-path').value || undefined,
        model_path: document.getElementById('voice-model-path').value || undefined,
        language: document.getElementById('voice-language').value || undefined,
        threads: parseInt(document.getElementById('voice-threads').value) || undefined,
        piper_model: document.getElementById('voice-piper-model').value || undefined,
        piper_path: document.getElementById('voice-piper-path').value || undefined,
        conversational_timeout: parseInt(document.getElementById('voice-timeout').value) || undefined,
      },
    };

    try {
      const response = await fetch('/api/config', {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(config),
      });

      if (response.ok) {
        alert('Configuration saved successfully!');
      } else {
        const error = await response.json();
        alert(`Failed to save: ${error.error || 'Unknown error'}`);
      }
    } catch (error) {
      alert('Failed to save configuration');
    }
  }

  loadLogs() {
    const logsContainer = document.getElementById('logs-container');
    logsContainer.innerHTML = `
      <div class="log-entry">
        <span class="log-time">[${new Date().toISOString()}]</span>
        <span class="log-level-info">[INFO]</span>
        <span class="log-message">Crybot Web UI initialized</span>
      </div>
    `;

    // TODO: Implement real-time log streaming via WebSocket or polling
  }

  escapeHtml(text) {
    const div = document.createElement('div');
    div.textContent = text;
    return div.innerHTML;
  }

  async activatePushToTalk() {
    if (this.pushToTalkActive) return;

    try {
      const response = await fetch('/api/voice/push-to-talk', {
        method: 'POST',
      });

      if (response.ok) {
        this.pushToTalkActive = true;
        const pttBtn = document.querySelector('.push-to-talk-btn');
        if (pttBtn) {
          pttBtn.textContent = 'Listening...';
          pttBtn.style.backgroundColor = '#27ae60';
        }
      }
    } catch (error) {
      console.error('Failed to activate push-to-talk:', error);
    }
  }

  async deactivatePushToTalk() {
    if (!this.pushToTalkActive) return;

    try {
      const response = await fetch('/api/voice/push-to-talk', {
        method: 'DELETE',
      });

      if (response.ok) {
        this.pushToTalkActive = false;
        const pttBtn = document.querySelector('.push-to-talk-btn');
        if (pttBtn) {
          pttBtn.textContent = 'Push to talk';
          pttBtn.style.backgroundColor = '';
        }
      }
    } catch (error) {
      console.error('Failed to deactivate push-to-talk:', error);
    }
  }

  async loadSessionsList() {
    try {
      const response = await fetch('/api/sessions');
      const data = await response.json();

      const listContainer = document.getElementById('chat-list');
      if (!listContainer) return;

      listContainer.innerHTML = '';

      if (!data.sessions || data.sessions.length === 0) {
        listContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No conversations yet. Start chatting!</p>';
        return;
      }

      // Filter to show web_ and repl_ sessions, plus "repl" and "cli" (not telegram or voice)
      const chatSessions = data.sessions.filter(s =>
        s.startsWith('web_') ||
        s.startsWith('repl_') ||
        s === 'repl' ||
        s === 'cli'
      );

      if (chatSessions.length === 0) {
        listContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No conversations yet. Start chatting!</p>';
        return;
      }

      // Check each session for messages and filter out empty ones
      const sessionsWithMessages = [];

      for (const sessionId of chatSessions) {
        try {
          const sessionResponse = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}`);
          const sessionData = await sessionResponse.json();

          // Filter out messages that have actual content (not just system/tool messages)
          const userMessages = sessionData.messages.filter(m =>
            m.content && (m.role === 'user' || m.role === 'assistant')
          );

          if (userMessages.length > 0) {
            sessionsWithMessages.push({
              id: sessionId,
              lastMessage: userMessages[userMessages.length - 1].content,
              messageCount: userMessages.length,
            });
          }
        } catch (e) {
          console.error('Failed to load session:', sessionId, e);
        }
      }

      if (sessionsWithMessages.length === 0) {
        listContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No conversations yet. Start chatting!</p>';
        return;
      }

      // Sort sessions by ID (newest first based on timestamp prefix)
      sessionsWithMessages.sort((a, b) => b.id.localeCompare(a.id));

      sessionsWithMessages.forEach(session => {
        const item = document.createElement('div');
        item.className = 'chat-conversation-item';
        item.dataset.sessionId = session.id;

        // Get session info
        const sessionInfo = this.formatSessionInfo(session.id, session.lastMessage);
        const isCurrent = session.id === this.sessionId;

        item.innerHTML = `
          <div class="chat-conversation-content">
            <div class="chat-conversation-title">${this.escapeHtml(sessionInfo.title)}</div>
            <div class="chat-conversation-preview">${this.escapeHtml(sessionInfo.preview)}</div>
            <div class="chat-conversation-time">${sessionInfo.time}</div>
          </div>
          <button class="chat-conversation-delete" data-session="${session.id}" title="Delete conversation">×</button>
        `;

        if (isCurrent) {
          item.classList.add('active');
        }

        // Click on item opens the chat
        item.addEventListener('click', (e) => {
          // Don't open if clicking the delete button
          if (!e.target.classList.contains('chat-conversation-delete')) {
            this.openChatSession(session.id);
          }
        });

        // Delete button click handler
        const deleteBtn = item.querySelector('.chat-conversation-delete');
        deleteBtn.addEventListener('click', (e) => {
          e.stopPropagation();
          this.deleteSession(session.id);
        });

        listContainer.appendChild(item);
      });
    } catch (error) {
      console.error('Failed to load sessions:', error);
    }
  }

  formatSessionInfo(sessionId, lastMessage) {
    // Parse session ID and format for display
    let title = 'Conversation';
    let preview = lastMessage || 'No messages';
    let time = '';

    if (sessionId.startsWith('web_')) {
      title = 'Web Chat';
      // Extract timestamp from session ID
      const timestamp = sessionId.substring(4);
      if (timestamp.length >= 8) {
        time = this.formatSessionTime(timestamp.substring(0, 8));
      }
    } else if (sessionId.startsWith('repl_')) {
      title = 'REPL Session';
      const timestamp = sessionId.substring(5);
      if (timestamp.length >= 8) {
        time = this.formatSessionTime(timestamp.substring(0, 8));
      }
    } else if (sessionId === 'repl') {
      title = 'REPL Session';
    } else if (sessionId === 'cli') {
      title = 'CLI Command';
    }

    // Truncate preview if too long
    if (preview && preview.length > 50) {
      preview = preview.substring(0, 50) + '...';
    }

    return { title, preview, time };
  }

  formatSessionTime(hexTime) {
    try {
      // Convert hex timestamp to readable time
      const timestamp = parseInt(hexTime, 16);
      const date = new Date(timestamp * 1000);
      const now = new Date();
      const diffMs = now.getTime() - date.getTime();
      const diffDays = Math.floor(diffMs / (1000 * 60 * 60 * 24));

      if (diffDays === 0) {
        return date.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' });
      } else if (diffDays === 1) {
        return 'Yesterday';
      } else if (diffDays < 7) {
        return date.toLocaleDateString([], { weekday: 'short' });
      } else {
        return date.toLocaleDateString([], { month: 'short', day: 'numeric' });
      }
    } catch {
      return '';
    }
  }

  async openChatSession(sessionId) {
    // Show chat view
    this.showChatView();

    // Load messages for this session
    try {
      const response = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}`);
      const data = await response.json();

      // Update current session
      this.sessionId = sessionId;
      localStorage.setItem('crybotChatSession', sessionId);

      const container = document.getElementById('chat-messages');
      container.innerHTML = '';

      if (!data.messages || data.messages.length === 0) {
        container.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No messages yet. Start a conversation!</p>';
        return;
      }

      // Display messages (filter out system messages)
      data.messages.forEach(msg => {
        if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
          this.addMessage(msg.content, msg.role, 'chat-messages');
        }
      });

      // Refresh list to update active state
      this.loadSessionsList();
    } catch (error) {
      console.error('Failed to load session:', error);
    }
  }

  showChatList() {
    const listContainer = document.getElementById('chat-list');
    const chatView = document.getElementById('chat-view');

    listContainer?.classList.remove('hidden');
    chatView?.classList.add('hidden');

    // Save view state
    this.chatViewVisible = false;
    localStorage.setItem('crybotChatViewVisible', 'false');

    // Refresh the list to show latest state
    this.loadSessionsList();
  }

  async deleteSession(sessionId) {
    if (!confirm('Are you sure you want to delete this conversation?')) {
      return;
    }

    try {
      const response = await fetch(`/api/sessions/${encodeURIComponent(sessionId)}`, {
        method: 'DELETE',
      });

      if (response.ok) {
        // If we deleted the current session, go back to list
        if (sessionId === this.sessionId) {
          this.showChatList();
          this.sessionId = null;
          localStorage.removeItem('crybotChatSession');
        }
        // Refresh the list
        this.loadSessionsList();
      } else {
        alert('Failed to delete conversation');
      }
    } catch (error) {
      console.error('Failed to delete session:', error);
      alert('Failed to delete conversation');
    }
  }

  showChatView() {
    const listContainer = document.getElementById('chat-list');
    const chatView = document.getElementById('chat-view');

    listContainer?.classList.add('hidden');
    chatView?.classList.remove('hidden');

    // Save view state
    this.chatViewVisible = true;
    localStorage.setItem('crybotChatViewVisible', 'true');
  }

  switchSession(sessionId) {
    if (!sessionId) return;

    // Show the chat view when switching to a session
    this.showChatView();

    // Switch to the selected session via WebSocket
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'session_switch',
        session_id: sessionId,
      }));
    }
  }

  createNewChat() {
    // Show the chat view for new chat
    this.showChatView();

    // Create a new session by sending empty session_id
    if (this.ws && this.ws.readyState === WebSocket.OPEN) {
      this.ws.send(JSON.stringify({
        type: 'session_switch',
        session_id: '', // Empty means create new
      }));
    }
  }

  // Skills Management
  async loadSkills() {
    const grid = document.getElementById('skills-grid');
    grid.innerHTML = '<p style="color: #666; grid-column: 1/-1;">Loading skills...</p>';

    try {
      const response = await fetch('/api/skills');
      const data = await response.json();

      if (!data.skills || data.skills.length === 0) {
        grid.innerHTML = '<p style="color: #999; grid-column: 1/-1; text-align: center; padding: 40px;">No skills found. Click "+ Add Skill" to create one.</p>';
        return;
      }

      grid.innerHTML = '';
      data.skills.forEach(skill => {
        const card = this.createSkillCard(skill);
        grid.appendChild(card);
      });
    } catch (error) {
      console.error('Failed to load skills:', error);
      grid.innerHTML = '<p style="color: #e74c3c; grid-column: 1/-1;">Failed to load skills.</p>';
    }
  }

  createSkillCard(skill) {
    const card = document.createElement('div');
    card.className = 'skill-card';
    card.dataset.skillName = skill.dir_name;

    const isLoaded = skill.loaded;
    const hasConfig = skill.has_config;
    const configValid = skill.config_valid;
    const envStatus = skill.env_status;

    let statusBadge = '<span class="skill-badge skill-badge-gray">No Config</span>';
    if (hasConfig) {
      if (!configValid) {
        statusBadge = '<span class="skill-badge skill-badge-red">Invalid Config</span>';
      } else if (envStatus === 'missing') {
        statusBadge = '<span class="skill-badge skill-badge-yellow">Missing Env</span>';
      } else if (isLoaded) {
        statusBadge = '<span class="skill-badge skill-badge-green">Loaded</span>';
      } else {
        statusBadge = '<span class="skill-badge skill-badge-blue">Configured</span>';
      }
    }

    const toolName = skill.config?.tool_name || skill.dir_name;
    const description = skill.config?.description || skill.config?.tool_description || 'No description';
    const version = skill.config?.version || '?';

    card.innerHTML = `
      <div class="skill-card-header">
        <h3>${this.escapeHtml(toolName)}</h3>
        ${statusBadge}
      </div>
      <p class="skill-card-description">${this.escapeHtml(description)}</p>
      <div class="skill-card-meta">
        <span>v${this.escapeHtml(version)}</span>
        ${skill.has_docs ? '<span title="Has documentation">📄</span>' : ''}
      </div>
      ${skill.config_error ? `<p class="skill-card-error">Error: ${this.escapeHtml(skill.config_error)}</p>` : ''}
      ${skill.missing_env && skill.missing_env.length > 0 ? `
        <p class="skill-card-warning">
          Missing env vars: ${skill.missing_env.map(e => `<code>${this.escapeHtml(e)}</code>`).join(', ')}
        </p>
      ` : ''}
      <div class="skill-card-actions">
        <button class="btn-sm btn-edit" data-skill="${skill.dir_name}">Edit</button>
        <button class="btn-sm btn-delete" data-skill="${skill.dir_name}">Delete</button>
      </div>
    `;

    // Add click handlers
    card.querySelector('.btn-edit').addEventListener('click', () => this.openSkillEditor(skill.dir_name));
    card.querySelector('.btn-delete').addEventListener('click', () => this.deleteSkill(skill.dir_name));

    return card;
  }

  openSkillEditor(skillName) {
    const listView = document.getElementById('skills-list-view');
    const editorView = document.getElementById('skill-editor-view');
    const title = document.getElementById('skill-editor-title');

    listView.classList.add('hidden');
    editorView.classList.remove('hidden');
    title.textContent = `Edit Skill: ${skillName}`;

    // Initialize CodeMirror editors if not already done
    this.initCodeMirrorEditors();

    // Load skill data
    this.loadSkillForEditor(skillName);

    // Setup skill editor tabs
    this.setupSkillEditorTabs();
  }

  initCodeMirrorEditors() {
    if (!this.configEditor) {
      const configTextarea = document.getElementById('skill-config');
      this.configEditor = CodeMirror.fromTextArea(configTextarea, {
        mode: 'yaml',
        theme: 'default',
        lineNumbers: true,
        indentUnit: 2,
        tabSize: 2,
        indentWithTabs: false,
        lineWrapping: true,
        autofocus: false,
      });
    }

    if (!this.docsEditor) {
      const docsTextarea = document.getElementById('skill-docs');
      this.docsEditor = CodeMirror.fromTextArea(docsTextarea, {
        mode: 'markdown',
        theme: 'default',
        lineNumbers: true,
        indentUnit: 2,
        tabSize: 2,
        indentWithTabs: false,
        lineWrapping: true,
        autofocus: false,
      });
    }
  }

  async loadSkillForEditor(skillName) {
    try {
      const response = await fetch(`/api/skills/${encodeURIComponent(skillName)}`);
      const data = await response.json();

      document.getElementById('skill-dir-name').value = data.name || skillName;

      // Update CodeMirror editors
      if (this.configEditor) {
        this.configEditor.setValue(data.config_yaml || '');
      }
      if (this.docsEditor) {
        this.docsEditor.setValue(data.docs || '');
      }

      // Load credentials
      this.loadCredentials(data.config);
    } catch (error) {
      console.error('Failed to load skill:', error);
      alert('Failed to load skill data');
    }
  }

  loadCredentials(config) {
    const container = document.getElementById('credentials-container');
    container.innerHTML = '';

    if (!config || !config.credentials || config.credentials.length === 0) {
      container.innerHTML = '<p style="color: #999;">No credentials required for this skill.</p>';
      return;
    }

    config.credentials.forEach(cred => {
      const div = document.createElement('div');
      div.className = 'form-group';
      div.innerHTML = `
        <label>${this.escapeHtml(cred.description)}</label>
        <input type="password" class="credential-input" data-cred="${cred.name}" placeholder="${cred.placeholder || 'Enter ' + cred.name + '...'}">
        ${cred.required ? '<small>Required</small>' : '<small>Optional</small>'}
      `;
      container.appendChild(div);
    });
  }

  setupSkillEditorTabs() {
    const tabs = document.querySelectorAll('.skill-tab');
    tabs.forEach(tab => {
      tab.onclick = (e) => {
        const tabId = tab.dataset.tab;
        document.querySelectorAll('.skill-tab').forEach(t => t.classList.remove('active'));
        document.querySelectorAll('.skill-tab-content').forEach(c => c.classList.remove('active'));
        tab.classList.add('active');
        document.getElementById(tabId).classList.add('active');
      };
    });
  }

  closeSkillEditor() {
    const listView = document.getElementById('skills-list-view');
    const editorView = document.getElementById('skill-editor-view');

    listView.classList.remove('hidden');
    editorView.classList.add('hidden');

    // Reload skills list
    this.loadSkills();
  }

  async saveSkill() {
    const skillName = document.getElementById('skill-dir-name').value;
    const config = this.configEditor ? this.configEditor.getValue() : '';
    const docs = this.docsEditor ? this.docsEditor.getValue() : '';

    try {
      const response = await fetch(`/api/skills/${encodeURIComponent(skillName)}`, {
        method: 'PUT',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: skillName,
          config: config,
          docs: docs || null,
        }),
      });

      const data = await response.json();

      if (data.success) {
        alert('Skill saved successfully! Reload skills to apply changes.');
        // Optionally auto-reload
        // this.reloadSkills();
      } else {
        alert(`Failed to save: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to save skill:', error);
      alert('Failed to save skill');
    }
  }

  async deleteSkill(skillName) {
    if (!confirm(`Are you sure you want to delete the skill "${skillName}"?`)) {
      return;
    }

    try {
      const response = await fetch(`/api/skills/${encodeURIComponent(skillName)}`, {
        method: 'DELETE',
      });

      const data = await response.json();

      if (data.success) {
        alert('Skill deleted successfully');
        this.loadSkills();
      } else {
        alert(`Failed to delete: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to delete skill:', error);
      alert('Failed to delete skill');
    }
  }

  async reloadSkills() {
    try {
      const response = await fetch('/api/agent/reload-skills', {
        method: 'POST',
      });

      const data = await response.json();

      if (data.success) {
        let message = `Skills reloaded: ${data.loaded} loaded successfully`;
        if (data.missing > 0) {
          message += `, ${data.missing} missing credentials`;
        }
        if (data.errors > 0) {
          message += `, ${data.errors} errors`;
        }

        // Show detailed results if there are issues
        if (data.results && data.results.length > 0) {
          const errorResults = data.results.filter(r => r.status !== 'loaded');
          if (errorResults.length > 0) {
            message += '\n\nDetails:\n';
            errorResults.forEach(r => {
              if (r.status === 'missing_credentials') {
                message += `\n⚠️ ${r.name}: ${r.error}`;
              } else if (r.status === 'error') {
                message += `\n❌ ${r.name}: ${r.error}`;
              }
            });
          }
        }

        if (data.loaded > 0 && data.missing === 0 && data.errors === 0) {
          message += '\n\n✓ All skills loaded and ready to use!';
        } else if (data.loaded > 0) {
          message += '\n\n✓ Loaded skills are ready to use.';
        }

        alert(message);
        this.loadSkills();
      } else {
        alert('Failed to reload skills');
      }
    } catch (error) {
      console.error('Failed to reload skills:', error);
      alert('Failed to reload skills: ' + error.message);
    }
  }

  openCreateSkillModal() {
    const modal = document.getElementById('create-skill-modal');
    modal.classList.remove('hidden');
  }

  closeCreateSkillModal() {
    const modal = document.getElementById('create-skill-modal');
    modal.classList.add('hidden');
    document.getElementById('new-skill-name').value = '';
  }

  async createSkill() {
    const name = document.getElementById('new-skill-name').value.trim();
    const template = document.getElementById('new-skill-template').value;

    if (!name) {
      alert('Please enter a skill name');
      return;
    }

    // Validate name format
    if (!/^[a-z0-9_\-]+$/.test(name)) {
      alert('Skill name must contain only lowercase letters, numbers, hyphens, and underscores');
      return;
    }

    // Get template and replace name placeholder
    let config = this.getSkillTemplate(template);
    config = config.replace(/^name: new_skill$/m, `name: ${name}`);

    try {
      const response = await fetch('/api/skills', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name: name,
          config: config,
          docs: `# ${name}\n\nDescription of your skill goes here.`,
        }),
      });

      const data = await response.json();

      if (data.success) {
        this.closeCreateSkillModal();
        alert('Skill created successfully!');
        this.loadSkills();
        this.openSkillEditor(name);
      } else {
        alert(`Failed to create: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to create skill:', error);
      alert('Failed to create skill');
    }
  }

  async saveCredentials() {
    const inputs = document.querySelectorAll('.credential-input');
    const skillName = document.getElementById('skill-dir-name').value;
    const credentials = {};

    inputs.forEach(input => {
      if (input.value.trim()) {
        credentials[input.dataset.cred] = input.value.trim();
      }
    });

    try {
      const response = await fetch('/api/skills/credentials', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          skill: skillName,
          credentials: credentials,
        }),
      });

      const data = await response.json();

      if (data.success) {
        alert('Credentials saved successfully! Reload skills to apply changes.');
        // Optionally auto-reload
        // this.reloadSkills();
      } else {
        alert('Failed to save credentials: ' + (data.error || 'Unknown error'));
      }
    } catch (error) {
      console.error('Failed to save credentials:', error);
      alert('Failed to save credentials');
    }
  }

  // Create skill templates
  getSkillTemplate(type) {
    const templates = {
      blank: String.raw`name: new_skill
version: 1.0.0
description: Description of your skill

tool:
  name: tool_name
  description: What this tool does
  parameters:
    type: object
    properties:
      input:
        type: string
        description: Input parameter description
    required:
      - input

execution:
  type: http
  http:
    url: https://api.example.com/endpoint
    method: GET
    params:
      param: "{{input}}"
    response_format: |
      Result: {{field}}
`,
      weather: String.raw`name: weather
version: 1.0.0
description: Get current weather information for any location

tool:
  name: get_weather
  description: Get current weather for a location using OpenWeatherMap API
  parameters:
    type: object
    properties:
      location:
        type: string
        description: City name, state code, or country code (e.g., "London", "New York", "Tokyo")
      units:
        type: string
        description: Temperature units
        enum_values:
          - celsius
          - fahrenheit
        default: celsius
    required:
      - location

execution:
  type: http
  http:
    url: https://api.openweathermap.org/data/2.5/weather
    method: GET
    params:
      q: "{{location}}"
      units: "{% if units == 'fahrenheit' %}imperial{% else %}metric{% endif %}"
      appid: "\${credential:api_key}"
    response_format: |
      Weather in {{name}}, {{sys.country}}: {{weather[0].description}}
      Temperature: {{main.temp}}° {{main.feels_like}}° (feels like)
      Humidity: {{main.humidity}}%
      Wind: {{wind.speed}} m/s
      Conditions: {{weather[0].main}}

credentials:
  - name: api_key
    description: OpenWeatherMap API Key
    required: true
    placeholder: Get your free API key at https://openweathermap.org/api
`,
      command: String.raw`name: new_skill
version: 1.0.0
description: Execute an external command

tool:
  name: tool_name
  description: What this tool does
  parameters:
    type: object
    properties:
      input:
        type: string
        description: Input parameter
    required:
      - input

execution:
  type: command
  command:
    command: /path/to/script
    args:
      - "{{input}}"
    working_dir: /optional/path
`,
    };
    return templates[type] || templates.blank;
  }

  // Scheduled Tasks Management
  async loadScheduledTasks() {
    const grid = document.getElementById('scheduled-tasks-grid');
    grid.innerHTML = '<p style="color: #666; grid-column: 1/-1;">Loading tasks...</p>';

    try {
      const response = await fetch('/api/scheduled-tasks');
      const data = await response.json();

      if (!data.tasks || data.tasks.length === 0) {
        grid.innerHTML = '<p style="color: #999; grid-column: 1/-1; text-align: center; padding: 40px;">No scheduled tasks. Click "+ Add Task" to create one.</p>';
        return;
      }

      this.scheduledTasks = data.tasks;
      grid.innerHTML = '';
      data.tasks.forEach(task => {
        const card = this.createTaskCard(task);
        grid.appendChild(card);
      });
    } catch (error) {
      console.error('Failed to load scheduled tasks:', error);
      grid.innerHTML = '<p style="color: #e74c3c; grid-column: 1/-1;">Failed to load tasks.</p>';
    }
  }

  createTaskCard(task) {
    const card = document.createElement('div');
    card.className = 'task-card';

    const enabledBadge = task.enabled ?
      '<span class="task-badge task-badge-green">Enabled</span>' :
      '<span class="task-badge task-badge-gray">Disabled</span>';

    const lastRun = task.last_run ? new Date(task.last_run).toLocaleString() : 'Never';
    const nextRun = task.next_run ? new Date(task.next_run).toLocaleString() : 'Not scheduled';

    card.innerHTML = `
      <div class="task-card-header">
        <h3>${this.escapeHtml(task.name)}</h3>
        ${enabledBadge}
      </div>
      ${task.description ? `<p class="task-card-description">${this.escapeHtml(task.description)}</p>` : ''}
      <div class="task-card-meta">
        <span><strong>Interval:</strong> ${this.escapeHtml(task.interval)}</span>
        <span><strong>Last Run:</strong> ${lastRun}</span>
        <span><strong>Next Run:</strong> ${nextRun}</span>
      </div>
      <div class="task-card-actions">
        <button class="btn-sm btn-view" data-task="${task.id}">View Output</button>
        <button class="btn-sm btn-run" data-task="${task.id}">Run Now</button>
        <button class="btn-sm btn-edit" data-task="${task.id}">Edit</button>
        <button class="btn-sm btn-delete" data-task="${task.id}">Delete</button>
      </div>
    `;

    // Add click handlers
    card.querySelector('.btn-view').addEventListener('click', () => this.viewTaskOutput(task.id));
    card.querySelector('.btn-run').addEventListener('click', () => this.runTask(task.id));
    card.querySelector('.btn-edit').addEventListener('click', () => this.editTask(task.id));
    card.querySelector('.btn-delete').addEventListener('click', () => this.deleteTask(task.id));

    return card;
  }

  openTaskModal(task = null) {
    this.editingTaskId = task ? task.id : null;
    const title = document.getElementById('task-modal-title');

    if (task) {
      title.textContent = 'Edit Scheduled Task';
      document.getElementById('task-name').value = task.name;
      document.getElementById('task-description').value = task.description || '';
      document.getElementById('task-prompt').value = task.prompt;
      document.getElementById('task-interval').value = task.interval;
      document.getElementById('task-enabled').checked = task.enabled;
      document.getElementById('task-forward-to').value = task.forward_to || '';
      document.getElementById('task-memory-expiration').value = task.memory_expiration || '';
    } else {
      title.textContent = 'Add Scheduled Task';
      document.getElementById('task-name').value = '';
      document.getElementById('task-description').value = '';
      document.getElementById('task-prompt').value = '';
      document.getElementById('task-interval').value = '';
      document.getElementById('task-enabled').checked = true;
      document.getElementById('task-forward-to').value = '';
      document.getElementById('task-memory-expiration').value = '';
    }

    document.getElementById('task-modal').classList.remove('hidden');
  }

  closeTaskModal() {
    document.getElementById('task-modal').classList.add('hidden');
    this.editingTaskId = null;
  }

  editTask(taskId) {
    const task = this.scheduledTasks.find(t => t.id === taskId);
    if (task) {
      this.openTaskModal(task);
    }
  }

  async saveTask() {
    const name = document.getElementById('task-name').value.trim();
    const description = document.getElementById('task-description').value.trim();
    const prompt = document.getElementById('task-prompt').value.trim();
    const interval = document.getElementById('task-interval').value.trim();
    const enabled = document.getElementById('task-enabled').checked;
    const forwardTo = document.getElementById('task-forward-to').value.trim() || null;
    const memoryExpiration = document.getElementById('task-memory-expiration').value.trim() || null;

    if (!name || !prompt || !interval) {
      alert('Name, prompt, and interval are required');
      return;
    }

    try {
      const method = this.editingTaskId ? 'PUT' : 'POST';
      const url = this.editingTaskId ? `/api/scheduled-tasks/${this.editingTaskId}` : '/api/scheduled-tasks';

      const response = await fetch(url, {
        method: method,
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          name,
          description: description || null,
          prompt,
          interval,
          enabled,
          forward_to: forwardTo,
          memory_expiration: memoryExpiration,
        }),
      });

      const data = await response.json();

      if (data.success || (data.task && data.task.id)) {
        this.closeTaskModal();
        this.loadScheduledTasks();
        alert(this.editingTaskId ? 'Task updated successfully!' : 'Task created successfully!');
      } else {
        alert(`Failed to save task: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to save task:', error);
      alert('Failed to save task');
    }
  }

  async deleteTask(taskId) {
    const task = this.scheduledTasks.find(t => t.id === taskId);
    if (!confirm(`Are you sure you want to delete the task "${task.name}"?`)) {
      return;
    }

    try {
      const response = await fetch(`/api/scheduled-tasks/${taskId}`, {
        method: 'DELETE',
      });

      const data = await response.json();

      if (data.success) {
        this.loadScheduledTasks();
      } else {
        alert(`Failed to delete task: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to delete task:', error);
      alert('Failed to delete task');
    }
  }

  async runTask(taskId) {
    const task = this.scheduledTasks.find(t => t.id === taskId);
    if (!confirm(`Run task "${task.name}" now?`)) {
      return;
    }

    // Show loading indicator
    const runBtn = document.querySelector(`.btn-run[data-task="${taskId}"]`);
    if (runBtn) {
      runBtn.disabled = true;
      runBtn.textContent = 'Running...';
    }

    try {
      const response = await fetch(`/api/scheduled-tasks/${taskId}/run`, {
        method: 'POST',
      });

      const data = await response.json();

      if (data.success) {
        // Refresh task list to update last_run time
        await this.loadScheduledTasks();

        // Show success message and offer to view output
        const viewOutput = confirm(`Task "${task.name}" executed successfully!\n\nClick OK to view the output, or Cancel to close.`);
        if (viewOutput) {
          this.viewTaskOutput(taskId);
        }
      } else {
        alert(`Failed to run task: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to run task:', error);
      alert('Failed to run task: ' + error.message);
    } finally {
      // Re-enable button
      const runBtn = document.querySelector(`.btn-run[data-task="${taskId}"]`);
      if (runBtn) {
        runBtn.disabled = false;
        runBtn.textContent = 'Run Now';
      }
    }
  }

  async viewTaskOutput(taskId) {
    const sessionKey = `scheduled/${taskId}`;
    const modal = document.getElementById('task-output-modal');
    const title = document.getElementById('task-output-modal-title');
    const messagesContainer = document.getElementById('task-output-messages');

    // Store the current task session for sending messages
    this.currentTaskSession = sessionKey;

    title.textContent = `Task Output - ${taskId}`;
    messagesContainer.innerHTML = '<p style="color: #666; text-align: center; padding: 20px;">Loading...</p>';
    modal.classList.remove('hidden');

    try {
      const response = await fetch(`/api/sessions/${encodeURIComponent(sessionKey)}`);
      const data = await response.json();

      if (!data.messages || data.messages.length === 0) {
        messagesContainer.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No output yet. Run the task to generate output, or add a message below to start.</p>';
        return;
      }

      // Display messages as chat
      this.renderTaskMessages(data.messages);
    } catch (error) {
      console.error('Failed to load task output:', error);
      messagesContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load task output.</p>';
    }

    // Scroll to bottom
    this.scrollToTaskBottom();
  }

  renderTaskMessages(messages) {
    const container = document.getElementById('task-output-messages');
    container.innerHTML = '';

    if (!messages || messages.length === 0) {
      container.innerHTML = '<p style="color: #999; text-align: center; padding: 20px;">No messages yet.</p>';
      return;
    }

    messages.forEach(msg => {
      if (msg.content && (msg.role === 'user' || msg.role === 'assistant')) {
        this.addTaskMessage(msg.content, msg.role);
      }
    });
  }

  addTaskMessage(content, role) {
    const container = document.getElementById('task-output-messages');
    const messageEl = document.createElement('div');
    messageEl.className = `task-message ${role}`;

    const avatar = role === 'user' ? 'U' : 'C';

    // Parse markdown for assistant messages
    let renderedContent;
    if (role === 'assistant') {
      renderedContent = typeof marked !== 'undefined' ? marked.parse(content) : this.escapeHtml(content);
    } else {
      renderedContent = this.escapeHtml(content);
    }

    messageEl.innerHTML = `
      <div class="task-message-avatar">${avatar}</div>
      <div class="task-message-content">
        <div class="task-message-bubble">${renderedContent}</div>
      </div>
    `;

    container.appendChild(messageEl);
  }

  scrollToTaskBottom() {
    const container = document.getElementById('task-output-messages');
    container.scrollTop = container.scrollHeight;
  }

  async sendTaskOutputMessage() {
    const form = document.getElementById('task-output-form');
    const input = form.querySelector('.task-output-input');
    const content = input.value.trim();

    if (!content || !this.currentTaskSession) return;

    // Add user message to UI
    this.addTaskMessage(content, 'user');
    input.value = '';
    this.scrollToTaskBottom();

    // Show typing indicator
    this.showTaskTypingIndicator();

    try {
      const response = await fetch('/api/chat', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          session_id: this.currentTaskSession,
          content: content,
        }),
      });

      const data = await response.json();

      // Hide typing indicator
      this.hideTaskTypingIndicator();

      // Add assistant response
      if (data.content) {
        this.addTaskMessage(data.content, 'assistant');
        this.scrollToTaskBottom();
      }
    } catch (error) {
      console.error('Failed to send message:', error);
      this.hideTaskTypingIndicator();
      this.addTaskMessage('Failed to send message', 'system');
    }
  }

  showTaskTypingIndicator() {
    const container = document.getElementById('task-output-messages');
    const indicator = document.createElement('div');
    indicator.className = 'task-message assistant typing';
    indicator.id = 'task-typing-indicator';
    indicator.innerHTML = `
      <div class="task-message-avatar">C</div>
      <div class="task-message-content">
        <div class="task-message-bubble">
          <div class="typing-dots">
            <span></span>
            <span></span>
            <span></span>
          </div>
        </div>
      </div>
    `;
    container.appendChild(indicator);
    this.scrollToTaskBottom();
  }

  hideTaskTypingIndicator() {
    const indicator = document.getElementById('task-typing-indicator');
    if (indicator) {
      indicator.remove();
    }
  }

  closeTaskOutputModal() {
    document.getElementById('task-output-modal').classList.add('hidden');
    this.currentTaskSession = null;
  }

  async loadTelegramChatsForForwarding() {
    const listContainer = document.getElementById('chats-list');
    const forwardChannel = document.getElementById('task-forward-channel').value;

    listContainer.innerHTML = '<p style="color: #666;">Loading chats...</p>';
    listContainer.classList.remove('hidden');

    try {
      const response = await fetch('/api/telegram/conversations');
      const data = await response.json();

      if (!data.conversations || data.conversations.length === 0) {
        listContainer.innerHTML = '<p style="color: #999;">No Telegram conversations found.</p>';
        return;
      }

      listContainer.innerHTML = '<div style="margin-top: 8px;"><strong>Select a chat to forward to:</strong></div>';

      data.conversations.forEach(conv => {
        const item = document.createElement('div');
        item.className = 'telegram-chat-option';
        item.textContent = conv.title || conv.id;
        item.style.cursor = 'pointer';
        item.style.padding = '4px 8px';
        item.style.borderRadius = '4px';
        item.style.marginTop = '4px';
        item.style.backgroundColor = '#f5f5f5';

        item.addEventListener('click', () => {
          // Extract actual chat_id from session_id (format: telegram_<chat_id>)
          // The session_id uses underscore instead of colon for filesystem safety
          const actualChatId = conv.id.replace(/^telegram_/, '');
          document.getElementById('task-forward-to').value = `telegram:${actualChatId}`;
          listContainer.classList.add('hidden');
        });

        item.addEventListener('mouseover', () => {
          item.style.backgroundColor = '#e3f2fd';
        });

        item.addEventListener('mouseout', () => {
          item.style.backgroundColor = '#f5f5f5';
        });

        listContainer.appendChild(item);
      });
    } catch (error) {
      console.error('Failed to load telegram chats:', error);
      listContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load chats.</p>';
    }
  }

  async loadWebSessionsForForwarding() {
    const listContainer = document.getElementById('chats-list');

    listContainer.innerHTML = '<p style="color: #666;">Loading sessions...</p>';
    listContainer.classList.remove('hidden');

    try {
      const response = await fetch('/api/sessions');
      const data = await response.json();

      if (!data.sessions || data.sessions.length === 0) {
        listContainer.innerHTML = '<p style="color: #999;">No web sessions found.</p>';
        return;
      }

      // Filter out telegram and scheduled sessions
      const webSessions = data.sessions.filter(s => !s.startsWith('telegram_') && !s.startsWith('scheduled/'));

      if (webSessions.length === 0) {
        listContainer.innerHTML = '<p style="color: #999;">No web sessions found (only showing non-Telegram/scheduled).</p>';
        return;
      }

      listContainer.innerHTML = '<div style="margin-top: 8px;"><strong>Select a session to forward to:</strong></div>';

      webSessions.forEach(sessionId => {
        const item = document.createElement('div');
        item.className = 'telegram-chat-option';
        item.textContent = sessionId;
        item.style.cursor = 'pointer';
        item.style.padding = '4px 8px';
        item.style.borderRadius = '4px';
        item.style.marginTop = '4px';
        item.style.backgroundColor = '#f5f5f5';

        item.addEventListener('click', () => {
          document.getElementById('task-forward-to').value = `web:${sessionId}`;
          listContainer.classList.add('hidden');
        });

        item.addEventListener('mouseover', () => {
          item.style.backgroundColor = '#e3f2fd';
        });

        item.addEventListener('mouseout', () => {
          item.style.backgroundColor = '#f5f5f5';
        });

        listContainer.appendChild(item);
      });
    } catch (error) {
      console.error('Failed to load web sessions:', error);
      listContainer.innerHTML = '<p style="color: #e74c3c;">Failed to load sessions.</p>';
    }
  }

  async reloadScheduledTasks() {
    try {
      const response = await fetch('/api/scheduled-tasks/reload', {
        method: 'POST',
      });

      const data = await response.json();

      if (data.success) {
        this.loadScheduledTasks();
        alert('Tasks reloaded successfully!');
      } else {
        alert(`Failed to reload tasks: ${data.error || 'Unknown error'}`);
      }
    } catch (error) {
      console.error('Failed to reload tasks:', error);
      alert('Failed to reload tasks');
    }
  }
}

// Global app reference for onclick handlers
let app;

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  app = new CrybotWeb();
});
