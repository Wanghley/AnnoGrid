from diagrams import Diagram, Cluster, Edge
from diagrams.onprem.compute import Server
from diagrams.onprem.network import Internet
from diagrams.generic.device import Mobile
from diagrams.onprem.monitoring import Prometheus, Grafana

# Ultra-high resolution with massive fonts - 4K optimized 16:9
graph_attr = {
    "fontsize": "72",  # Massive title font
    "fontname": "Helvetica Neue Black",
    "bgcolor": "#ffffff",
    "pad": "3.0",
    "splines": "ortho",  # Clean orthogonal lines for better organization
    "rankdir": "LR",
    "nodesep": "5.0",    # More spacing between nodes
    "ranksep": "8.0",    # Much more spacing between layers
    "compound": "true",
    "overlap": "false",
    "sep": "+50",
    "size": "40,22.5!",  # Even larger canvas
    "ratio": "fill",
    "dpi": "300",
    "resolution": "300"
}

# Massive node styling for maximum readability
node_attr = {
    "fontsize": "28",    # Much larger node text
    "fontname": "Helvetica Neue Bold",
    "fontcolor": "#ffffff",
    "width": "6.0",      # Bigger nodes
    "height": "4.5",
    "style": "filled,rounded",
    "fillcolor": "#2c3e50",
    "color": "#34495e",
    "penwidth": "4",
    "margin": "0.5",
    "fixedsize": "true"
}

# Massive edge styling
edge_attr = {
    "fontsize": "20",    # Much larger edge labels
    "fontname": "Helvetica Neue Bold",
    "fontcolor": "#1a1a1a",
    "color": "#2c3e50",
    "penwidth": "6.0",   # Thicker lines
    "arrowsize": "2.0",  # Bigger arrows
    "arrowhead": "vee",
    "minlen": "3"
}

with Diagram("ANNONΑΣ HOME LAB ARCHITECTURE", 
             show=False, 
             direction="LR",
             filename="home_lab_architecture",
             graph_attr=graph_attr, 
             node_attr=node_attr,
             edge_attr=edge_attr):
    
    # LAYER 1: CLIENT ACCESS
    with Cluster("CLIENT ACCESS LAYER", 
                 graph_attr={
                     "bgcolor": "#e3f2fd",
                     "style": "rounded,filled",
                     "penwidth": "5",
                     "color": "#0d47a1",
                     "fontsize": "36", 
                     "fontname": "Helvetica Neue Black", 
                     "fontcolor": "#0d47a1",
                     "margin": "60",
                     "labelloc": "t"  # Label at top
                 }):
        mobile = Mobile("MOBILE\nDEVICES")
        desktop = Server("DESKTOP\n& LAPTOP")
    
    # LAYER 2: EXTERNAL NETWORK
    with Cluster("EXTERNAL NETWORK", 
                 graph_attr={
                     "bgcolor": "#f5f5f5",
                     "style": "rounded,filled",
                     "penwidth": "5",
                     "color": "#424242",
                     "fontsize": "36", 
                     "fontname": "Helvetica Neue Black", 
                     "fontcolor": "#212121",
                     "margin": "60",
                     "labelloc": "t"
                 }):
        internet = Internet("INTERNET\nWAN")
    
    # LAYER 3: ANNONΑΣ INFRASTRUCTURE
    with Cluster("ANNONΑΣ INFRASTRUCTURE", 
                 graph_attr={
                     "bgcolor": "#e8f5e8",
                     "style": "rounded,filled",
                     "penwidth": "6",
                     "color": "#1b5e20",
                     "fontsize": "42", 
                     "fontname": "Helvetica Neue Black", 
                     "fontcolor": "#1b5e20",
                     "margin": "80",
                     "labelloc": "t"
                 }):
        
        # SUB-LAYER 3A: GATEWAY & MONITORING
        with Cluster("GATEWAY & MONITORING", 
                     graph_attr={
                         "bgcolor": "#fff8e1",
                         "style": "rounded,filled",
                         "penwidth": "4",
                         "color": "#e65100",
                         "fontsize": "28",
                         "fontname": "Helvetica Neue Bold",
                         "fontcolor": "#bf360c",
                         "margin": "50",
                         "labelloc": "t"
                     }):
            gateway = Server("GATEWAY\nRPi 3B+\nanno-gw-mon")
            prometheus = Prometheus("PROMETHEUS\nMETRICS")
            grafana = Grafana("GRAFANA\nDASHBOARDS")
        
        # SUB-LAYER 3B: CORE SERVICES
        with Cluster("CORE SERVICES", 
                     graph_attr={
                         "bgcolor": "#fce4ec",
                         "style": "rounded,filled",
                         "penwidth": "4",
                         "color": "#880e4f",
                         "fontsize": "28",
                         "fontname": "Helvetica Neue Bold",
                         "fontcolor": "#880e4f",
                         "margin": "50",
                         "labelloc": "t"
                     }):
            nas = Server("NAS STORAGE\nRPi 3B+\nanno-nas")
            app_server = Server("APP SERVER\nOrange Pi 3B\nanno-app")
    
    # ORGANIZED DATA FLOWS WITH MASSIVE LABELS
    
    # CLIENT → INTERNET (Blue - External Access)
    mobile >> Edge(
        label="HTTPS\nACCESS", 
        color="#1976d2", 
        penwidth="8", 
        style="bold",
        fontcolor="#0d47a1",
        fontsize="18"
    ) >> internet
    
    desktop >> Edge(
        label="SECURE\nWEB ACCESS", 
        color="#1976d2", 
        penwidth="8", 
        style="bold",
        fontcolor="#0d47a1",
        fontsize="18"
    ) >> internet
    
    # INTERNET → GATEWAY (Red - WAN Connection)
    internet >> Edge(
        label="WAN\nCONNECTION", 
        color="#d32f2f", 
        penwidth="10", 
        style="bold",
        fontcolor="#b71c1c",
        fontsize="22"
    ) >> gateway
    
    # GATEWAY → SERVICES (Green/Purple - Internal Routing)
    gateway >> Edge(
        label="REVERSE\nPROXY", 
        color="#388e3c", 
        penwidth="8", 
        style="dashed",
        fontcolor="#1b5e20",
        fontsize="18"
    ) >> nas
    
    gateway >> Edge(
        label="LOAD\nBALANCE", 
        color="#7b1fa2", 
        penwidth="8", 
        style="dashed",
        fontcolor="#4a148c",
        fontsize="18"
    ) >> app_server
    
    # APP → NAS (Orange - Data Storage)
    app_server >> Edge(
        label="DATA\nSTORAGE", 
        color="#f57c00", 
        penwidth="6", 
        style="dotted",
        fontcolor="#e65100",
        fontsize="16"
    ) >> nas
    
    # MONITORING FLOWS (Cyan - Observability)
    nas >> Edge(
        label="METRICS", 
        color="#00acc1", 
        penwidth="5", 
        style="dotted",
        fontcolor="#006064",
        fontsize="14"
    ) >> prometheus
    
    app_server >> Edge(
        label="METRICS", 
        color="#00acc1", 
        penwidth="5", 
        style="dotted",
        fontcolor="#006064",
        fontsize="14"
    ) >> prometheus
    
    prometheus >> Edge(
        label="DASHBOARD\nDATA", 
        color="#8e24aa", 
        penwidth="5", 
        style="dotted",
        fontcolor="#4a148c",
        fontsize="14"
    ) >> grafana