# Level 0 - Context Diagram
User -> System (Tag Submission)
User <- System (Travel Intelligence)

# Level 1 - Main Processes
1.) User (GPS, Tags)
2.) P1 Tag Contribution Processing (GPS to Hex ID, Check if Hex is Restricted, Tag)
3.) P2 Zone Aggregation Engine (Aggregated Zone Data)
4.) P3 Zone Intelligence
5.) P4 Map Renderer (Zone Display for Users)

# Data Storage
## D1 — Zone Registry (Pre-defined + Restricted)
     - Read-only at runtime
     - Researcher-defined pre-deployment
     - Contains: Zone IDs, zone types, restricted flags

## D2 — Pin Contributions Database
     - Write: Tag submission pipeline
     - Read: Zone aggregation engine
     - Contains: Zone ID, type, timestamp, contributor type
     - Does NOT contain: Raw GPS, user identity

## D3 — Zone Intelligence Database
     - Write: Zone intelligence generator
     - Read: Map renderer, zone detail screen
     - Contains: Zone intelligence records
     - Cached for performance

# Data Flow Summary
1. User (GPS + Tags)
2. [P1 Tag Processing] ──checks──► [D1 Zone Registry] (Anonymous Zone Report)
3. [D2 Tag Contributions] (Aggregated Data)
4. [P2 Zone Aggregation] ──reads──► [D1 Zone Registry] (Zone Intelligence)
5. [P3 Zone Intelligence] (Zone Records, Zone Data)
6. [D3 Zone Intelligence]
7. [P4 Map Renderer] (User, Map Display)
