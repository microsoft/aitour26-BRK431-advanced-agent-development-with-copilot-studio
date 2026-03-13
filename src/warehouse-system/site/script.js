// ZavaWarehouse Management System - JavaScript

// Data storage
let deliveries = [];
let tasks = [];
let taskIdCounter = 1;
let isLoggedIn = false;

// Initialize
document.addEventListener('DOMContentLoaded', function() {
    checkLoginStatus();
    setupLoginForm();
    generateDeliveryId();
    setupNavigation();
    setupFormSubmit();
    loadFromLocalStorage();
    updateStats();
});

// Login Management
function setupLoginForm() {
    const loginForm = document.getElementById('loginForm');
    loginForm.addEventListener('submit', function(e) {
        e.preventDefault();
        
        const username = document.getElementById('username').value;
        const password = document.getElementById('password').value;
        const errorDiv = document.getElementById('loginError');
        
        // Demo credentials
        if (username === 'admin' && password === 'warehouse2016') {
            isLoggedIn = true;
            localStorage.setItem('zavaLoggedIn', 'true');
            showMainApplication();
            errorDiv.style.display = 'none';
        } else {
            errorDiv.textContent = 'Invalid username or password. Please try again.';
            errorDiv.style.display = 'block';
            document.getElementById('password').value = '';
        }
    });
}

function checkLoginStatus() {
    const loggedIn = localStorage.getItem('zavaLoggedIn');
    if (loggedIn === 'true') {
        isLoggedIn = true;
        showMainApplication();
    }
}

function showMainApplication() {
    document.getElementById('loginScreen').style.display = 'none';
    document.getElementById('mainContainer').style.display = 'block';
}

function logout() {
    isLoggedIn = false;
    localStorage.removeItem('zavaLoggedIn');
    document.getElementById('loginScreen').style.display = 'flex';
    document.getElementById('mainContainer').style.display = 'none';
    document.getElementById('loginForm').reset();
}

// Navigation
function setupNavigation() {
    const navLinks = document.querySelectorAll('nav a');
    navLinks.forEach(link => {
        link.addEventListener('click', function(e) {
            e.preventDefault();
            
            // Update active nav
            navLinks.forEach(l => l.classList.remove('active'));
            this.classList.add('active');
            
            // Show/hide sections
            const sections = document.querySelectorAll('main > section');
            sections.forEach(s => s.style.display = 'none');
            
            const target = this.getAttribute('href').substring(1);
            if (target === 'new-delivery') {
                document.getElementById('new-delivery-section').style.display = 'block';
            } else if (target === 'tasks') {
                document.getElementById('tasks-section').style.display = 'block';
                displayTasks();
            } else if (target === 'reports') {
                document.getElementById('reports-section').style.display = 'block';
                updateStats();
            }
        });
    });
}

// Generate Delivery ID
function generateDeliveryId() {
    const timestamp = Date.now();
    const random = Math.floor(Math.random() * 1000);
    const deliveryId = 'DEL-' + timestamp.toString().substring(8) + '-' + random.toString().padStart(3, '0');
    document.getElementById('deliveryId').value = deliveryId;
}

// Line Items Management
function addLineItem() {
    const lineItemsContainer = document.getElementById('lineItems');
    const newLineItem = document.createElement('div');
    newLineItem.className = 'line-item';
    newLineItem.innerHTML = `
        <div class="form-row">
            <div class="form-group">
                <label>Product:</label>
                <input type="text" name="product[]" placeholder="Product name" required>
            </div>
            <div class="form-group">
                <label>Units:</label>
                <input type="number" name="units[]" placeholder="0" min="1" required>
            </div>
            <button type="button" class="btn-remove" onclick="removeLineItem(this)">Remove</button>
        </div>
    `;
    lineItemsContainer.appendChild(newLineItem);
}

function removeLineItem(button) {
    const lineItem = button.closest('.line-item');
    const container = document.getElementById('lineItems');
    if (container.children.length > 1) {
        lineItem.remove();
    } else {
        alert('At least one line item is required!');
    }
}

// Form Submission
function setupFormSubmit() {
    const form = document.getElementById('deliveryForm');
    form.addEventListener('submit', function(e) {
        e.preventDefault();
        
        const deliveryId = document.getElementById('deliveryId').value;
        const supplier = document.getElementById('supplier').value;
        const deliveryDate = new Date().toISOString().split('T')[0];
        
        // Get line items
        const products = document.querySelectorAll('input[name="product[]"]');
        const units = document.querySelectorAll('input[name="units[]"]');
        
        // Available warehouse locations
        const locations = [
            { code: 'A1', name: 'Aisle A - Section 1' },
            { code: 'A2', name: 'Aisle A - Section 2' },
            { code: 'B1', name: 'Aisle B - Section 1' },
            { code: 'B2', name: 'Aisle B - Section 2' },
            { code: 'C1', name: 'Aisle C - Section 1' },
            { code: 'C2', name: 'Aisle C - Section 2' }
        ];
        
        const lineItems = [];
        for (let i = 0; i < products.length; i++) {
            // Randomly assign a location for demo purposes
            const randomLocation = locations[Math.floor(Math.random() * locations.length)];
            
            lineItems.push({
                product: products[i].value,
                units: parseInt(units[i].value),
                location: randomLocation.code,
                locationName: randomLocation.name
            });
        }
        
        // Create delivery
        const delivery = {
            id: deliveryId,
            supplier: supplier,
            date: deliveryDate,
            lineItems: lineItems,
            createdAt: new Date().toISOString()
        };
        
        deliveries.push(delivery);
        
        // Generate tasks for each line item
        lineItems.forEach(item => {
            const task = {
                id: 'TASK-' + taskIdCounter.toString().padStart(5, '0'),
                deliveryId: deliveryId,
                product: item.product,
                units: item.units,
                location: item.location,
                locationName: item.locationName,
                supplier: supplier,
                status: 'pending',
                createdAt: new Date().toISOString()
            };
            tasks.push(task);
            taskIdCounter++;
        });
        
        // Save to localStorage
        saveToLocalStorage();
        
        // Reset form and generate new ID
        form.reset();
        generateDeliveryId();
        
        // Switch to tasks view
        document.querySelector('nav a[href="#tasks"]').click();
    });
}

// Display Tasks
function displayTasks(filter = 'all') {
    const tasksList = document.getElementById('tasksList');
    
    let filteredTasks = tasks;
    if (filter !== 'all') {
        filteredTasks = tasks.filter(task => task.status === filter);
    }
    
    if (filteredTasks.length === 0) {
        tasksList.innerHTML = '<p class="no-data">No tasks found.</p>';
        return;
    }
    
    tasksList.innerHTML = '';
    filteredTasks.reverse().forEach(task => {
        const taskCard = document.createElement('div');
        taskCard.className = 'task-card ' + task.status;
        taskCard.innerHTML = `
            <div class="task-header">
                <span class="task-id">${task.id}</span>
                <span class="task-status ${task.status}">${task.status.replace('-', ' ')}</span>
            </div>
            <div class="task-details">
                <strong>Product:</strong> ${task.product}<br>
                <strong>Units:</strong> ${task.units}<br>
                <strong>Destination:</strong> ${task.locationName} (${task.location})<br>
                <strong>Supplier:</strong> ${task.supplier}<br>
                <strong>Delivery:</strong> ${task.deliveryId}
            </div>
            <div class="task-actions">
                ${task.status === 'pending' ? '<button onclick="updateTaskStatus(\'' + task.id + '\', \'in-progress\')" class="btn-primary">Start Task</button>' : ''}
                ${task.status === 'in-progress' ? '<button onclick="updateTaskStatus(\'' + task.id + '\', \'completed\')" class="btn-primary">Complete Task</button>' : ''}
                ${task.status === 'completed' ? '<button onclick="updateTaskStatus(\'' + task.id + '\', \'pending\')" class="btn-secondary">Reset Task</button>' : ''}
            </div>
        `;
        tasksList.appendChild(taskCard);
    });
}

// Update Task Status
function updateTaskStatus(taskId, newStatus) {
    const task = tasks.find(t => t.id === taskId);
    if (task) {
        task.status = newStatus;
        saveToLocalStorage();
        displayTasks(document.querySelector('input[name="filter"]:checked').value);
        updateStats();
    }
}

// Filter Tasks
function filterTasks(filter) {
    displayTasks(filter);
}

// Update Statistics
function updateStats() {
    document.getElementById('totalDeliveries').textContent = deliveries.length;
    document.getElementById('totalTasks').textContent = tasks.length;
    document.getElementById('completedTasks').textContent = tasks.filter(t => t.status === 'completed').length;
    document.getElementById('pendingTasks').textContent = tasks.filter(t => t.status === 'pending').length;
}

// Local Storage
function saveToLocalStorage() {
    localStorage.setItem('zavaDeliveries', JSON.stringify(deliveries));
    localStorage.setItem('zavaTasks', JSON.stringify(tasks));
    localStorage.setItem('zavaTaskCounter', taskIdCounter.toString());
}

function loadFromLocalStorage() {
    const savedDeliveries = localStorage.getItem('zavaDeliveries');
    const savedTasks = localStorage.getItem('zavaTasks');
    const savedCounter = localStorage.getItem('zavaTaskCounter');
    
    if (savedDeliveries) {
        deliveries = JSON.parse(savedDeliveries);
    }
    
    if (savedTasks) {
        tasks = JSON.parse(savedTasks);
    }
    
    if (savedCounter) {
        taskIdCounter = parseInt(savedCounter);
    }
}