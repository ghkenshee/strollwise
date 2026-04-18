# strollwise
StrollWise Core Modules

1. H3-based Zone Engine
Definition:
The map is divided into hexagonal cells using H3
Each hex stores all activity inside its area
Hex grid removes irregular shapes from raw GPS data
Explanation:
Hexagons are the most ideal polygon shape
Requirements
• H3 library
• GPS input stream
• Resolution level control
• Mapping from lat long to hex ID
Key data inside each hex
• Number of reports
• Activity types
• Time distribution*
• Local vs international ratio
Features
• Batch-time zone updates
• Zone classification
• Density scoring
• Input for clustering module
User flow
• User walks or travels
• GPS captured every few seconds
• Each coordinate mapped to a hex
• Hex updates count and activity

H3 hexagonal maps serve as a benchmark for converting raw GPS noise into structured spatial intelligence units.

2. User Pinning
Raw GPS exposes user activity. GPS coordinates are converted into a hex ID for privacy. Users can pin hex into various activities such as food, shopping, sightseeing, nightlife, and transit.
Requirements
• Tag input interface
• Activity category list
• Timestamp logging
• Optional photo upload
Features:
Check in system where the users must be or were at the location to pin it
Approximate location (hex) and time period
Users can make their pin public, private, or anonymous

3. Cluster Algorithm and Aggregation
Mechanics:
A hex is visible if multiple users tag the same area
A user may check in a cluster to view detailed information about the zone, since zones cannot be generalized into a single definition.
Example: 50 users tag this hex as ‘food’; therefore, the system marks the hex as a food hotspot
Requirements:
If the number of users >= threshold value, then the zone is visible
The dominant tag defines the primary zone characteristic
Possible Algorithms:
DBSCAN for density clustering (finds clusters without a pre-defined number?, handles noise?, irregular travel patterns?)
K-nearest neighbor for refinement
There must be an algorithm where clusters can merge, with a max limit logic, and split if density drops.

Clustering converts raw movement data into behavioral spatial information.

4. Backend Database
Recommended Database Systems:
AWS DynamoDB (might be paid)

Tables & Data:
User Profiles (age range, type (lcl, intl), nationality, gender)
GPS coordinates
Hex id
Cluster id
Tags and activities
// I was thinking that the display information should be batch-time instead of real-time, which could be used as a test case to prevent " tagging attacks.

The backend ensures scalable, real-time data processing and batch-time information display.

5. Mapping API - converting back-end data into the Map UI
Recommended Systems:
✅ Leaflet.js (free, simple, prototype)
Mapbox
Google & Apple Maps (very expensive)
Requirements:
• API key
• Map SDK integration
• Layer configuration
Features:
Colored zones by local, international, and all (including mixed)
Heatmap visualization
Zone markers (this is a food hotspot)
Routing?
Layer examples
• Zone layer
• Traffic layer
• Hotspot layer
• Route layer
User flow
• User opens app
• Map loads
• Backend sends data
• Map renders zones and clusters

Map API translates data into an interactive visual experience.

FULL SYSTEM FLOW
Step by step
• User moves
• GPS collected
• Data mapped to H3 hex
• User tags activity
• Hex data updated
• Clustering runs
• Clusters stored
• Map displays results
Key innovation flow
Raw GPS → Hex zones → Tagged data → Clusters → Visual map

StrollWise converts raw movement into structured travel intelligence using H3 zoning, crowd-sourced tagging, and density-based clustering, then visualizes it in real time through an interactive map system.
