// Admin Dashboard JavaScript

document.addEventListener('DOMContentLoaded', function() {
    // Animate stats on page load
    animateStats();
    
    // Handle action buttons
    initActionButtons();
});

// Animate statistics numbers
function animateStats() {
    const statCards = document.querySelectorAll('.stat-card h3');
    
    statCards.forEach(stat => {
        const finalValue = stat.textContent.trim();
        const numericValue = parseFloat(finalValue.replace(/[^\d.]/g, ''));
        
        if (!isNaN(numericValue)) {
            let currentValue = 0;
            const increment = numericValue / 30;
            const unit = finalValue.replace(/[\d.]/g, '').trim();
            
            const timer = setInterval(() => {
                currentValue += increment;
                if (currentValue >= numericValue) {
                    currentValue = numericValue;
                    clearInterval(timer);
                }
                
                if (unit) {
                    stat.textContent = Math.floor(currentValue) + ' ' + unit;
                } else {
                    stat.textContent = Math.floor(currentValue);
                }
            }, 30);
        }
    });
}

// Initialize action buttons
function initActionButtons() {
    const actionButtons = document.querySelectorAll('.action-btn');
    
    actionButtons.forEach(button => {
        button.addEventListener('click', function() {
            const actionText = this.querySelector('span').textContent;
            console.log('Action clicked:', actionText);
            
            // Add ripple effect
            const ripple = document.createElement('span');
            ripple.className = 'ripple-effect';
            this.appendChild(ripple);
            
            setTimeout(() => ripple.remove(), 600);
        });
    });
}

// Update activity time dynamically (optional)
function updateActivityTimes() {
    const times = document.querySelectorAll('.activity-time');
    // You can implement real-time updates here if needed
}

// Add smooth scroll behavior
document.querySelectorAll('a[href^="#"]').forEach(anchor => {
    anchor.addEventListener('click', function(e) {
        e.preventDefault();
        const target = document.querySelector(this.getAttribute('href'));
        if (target) {
            target.scrollIntoView({
                behavior: 'smooth',
                block: 'start'
            });
        }
    });
});