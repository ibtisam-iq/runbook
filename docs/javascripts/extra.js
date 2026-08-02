(function() {
    var resizer = document.createElement("div");
    resizer.className = "md-sidebar-resizer";
    document.body.appendChild(resizer);

    var startX, startWidth;

    resizer.addEventListener("mousedown", function(e) {
        e.preventDefault();
        
        var currentSidebar = document.querySelector(".md-sidebar--primary");
        if (!currentSidebar) return;

        startX = e.clientX;
        startWidth = currentSidebar.getBoundingClientRect().width;
        
        document.body.style.userSelect = "none";
        document.documentElement.addEventListener("mousemove", doDrag, false);
        document.documentElement.addEventListener("mouseup", stopDrag, false);
    });

    resizer.addEventListener("dblclick", function() {
        window.location.reload();
    });

    // Clear legacy state to ensure a predictable default width
    localStorage.removeItem("sidebarWidth");

    function applyWidth(sidebarEl, width) {
        sidebarEl.style.setProperty("width", width + "px", "important");
        sidebarEl.style.setProperty("flex", "0 0 " + width + "px", "important");
        sidebarEl.style.setProperty("max-width", width + "px", "important");

        // Stretch root nav to match sidebar width, preserving native nested indentation
        var rootNav = sidebarEl.querySelector('.md-nav--primary');
        if (rootNav) {
            rootNav.style.setProperty("width", width + "px", "important");
            rootNav.style.setProperty("max-width", width + "px", "important");
        }

        var mainInner = document.querySelector('.md-main__inner');
        if (mainInner) {
            var rightSidebar = document.querySelector('.md-sidebar--secondary');
            var rightWidth = (rightSidebar && window.getComputedStyle(rightSidebar).display !== "none") ? "12.1rem" : "0px";
            
            mainInner.style.setProperty("display", "grid", "important");
            mainInner.style.setProperty("grid-template-columns", width + "px minmax(0, 1fr) " + rightWidth, "important");
        }
    }

    function doDrag(e) {
        var currentSidebar = document.querySelector(".md-sidebar--primary");
        if (!currentSidebar) return;

        var newWidth = startWidth + e.clientX - startX;
        if (newWidth > 200 && newWidth < 800) {
            applyWidth(currentSidebar, newWidth);
        }
    }

    function stopDrag() {
        document.body.style.userSelect = "";
        document.documentElement.removeEventListener("mousemove", doDrag, false);
        document.documentElement.removeEventListener("mouseup", stopDrag, false);
    }

    function updateResizerPosition() {
        var currentSidebar = document.querySelector(".md-sidebar--primary");
        
        if (!currentSidebar || window.innerWidth < 1220) {
            resizer.style.display = "none";
            return;
        }
        
        var rect = currentSidebar.getBoundingClientRect();
        if (rect.width > 0) {
            resizer.style.display = "block";
            resizer.style.left = (rect.right - 14) + "px";
            resizer.style.top = Math.max(rect.top, 0) + "px";
            resizer.style.height = rect.height + "px";
        } else {
            resizer.style.display = "none";
        }
    }

    window.addEventListener("resize", updateResizerPosition);
    document.addEventListener("scroll", updateResizerPosition);
    setInterval(updateResizerPosition, 100);
})();
