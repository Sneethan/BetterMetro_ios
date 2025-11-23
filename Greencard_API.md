# Greencard API Reference

This document summarises how the bundled MetroTas app talks to the Greencard API so the same flows can be recreated manually (for example via `curl`).

## Base URL Helper

All feature modules call `getAPIPath("<slug>")`, which resolves to:

```
https://greencard.metrotas.com.au/api/v1/<slug>/
```

The slug is one of `auth`, `account`, `history`, or `pages/top-up` depending on the feature.

## Authentication Scheme

- Every request uses HTTP Basic authentication; there are no tokens.
- Requests also merge in the mobile `User-Agent` header (`MetroTasMobile/<version>-<build> <platform>`).
- When using `curl`, pass `-u CARD_NUMBER:PASSWORD`. This automatically **base64-encodes the card number and password** to match how the app builds the `Authorization: Basic …` header.
- To mirror the mobile headers manually you can add `-H 'User-Agent: MetroTasMobile/2.0.5-233 android'` (Android) or `-H 'User-Agent: MetroTasMobile/4.0.4-264 ios'` (iOS).

## Endpoints

| Purpose              | Request                                                                                                                             | Notes                                                                                              |
|----------------------|--------------------------------------------------------------------------------------------------------------------------------------|----------------------------------------------------------------------------------------------------|
| Validate credentials | `curl 'https://greencard.metrotas.com.au/api/v1/auth/' -H 'User-Agent: …' -u CARD_NUMBER:PASSWORD`                                   | Returns `{ "success": true }` on valid card/password, otherwise `errors[0].message`.               |
| Fetch account + card | `curl 'https://greencard.metrotas.com.au/api/v1/account/' -H 'User-Agent: …' -u CARD_NUMBER:PASSWORD`                                | Response `data` contains `account` (profile) and `card` (balance, pending balance).               |
| Fetch history        | `curl 'https://greencard.metrotas.com.au/api/v1/history/' -H 'User-Agent: …' -u CARD_NUMBER:PASSWORD`                                | Returns array of trips/top-ups; the app sorts by `date` descending.                                |
| Update account       | `curl 'https://greencard.metrotas.com.au/api/v1/account/' -X PUT -H 'Content-Type: application/json' -H 'User-Agent: …' \\           |
|                      | `     -u CARD_NUMBER:PASSWORD --data '{"account":{…}}'`                                                                              | Body is the full account payload minus the immutable `username`.                                   |
| Top-up page          | `curl 'https://greencard.metrotas.com.au/api/v1/pages/top-up/' -H 'User-Agent: …' -u CARD_NUMBER:PASSWORD`                           | Same credentials are embedded when the native app opens its WebView.                               |

## Response Shape

Each call is expected to return:

```json
{
  "success": true,
  "data": { ... },
  "errors": [
    { "message": "..." }
  ]
}
```

If `"success"` is `false`, the client surfaces `errors[0].message`.

## Workflow Tips

1. Hit `auth/` first to check credentials.
2. Reuse the same Basic header (remember: the `Authorization` value **must** be base64 encoded).
3. Include the mobile `User-Agent` header for parity with the shipping app.

## Trip Planner / Network API (Routes & Real‑time)

The trip‑planner part of the app talks to two backends:

- A **REST network metadata API** for networks and timetables.
- A **GraphQL API** for stops, routes, trips, and real‑time vehicle/schedule information.

> Replace the placeholders below:
> - `<TRIPPLANNER_REST_BASE>` – the REST base URL (e.g. `https://…/api`).
> - `<TRIPPLANNER_GRAPHQL_ENDPOINT>` – the GraphQL HTTP endpoint (usually ends with `/graphql`).
>
> The compiled bundle only references abstract constants; the actual hosts are injected at runtime (likely via remote config), so you’ll need to capture them from a running app via a proxy.

### REST: Networks and Timetables

All REST calls use plain JSON:

- `GET <TRIPPLANNER_REST_BASE>/networks`
- `GET <TRIPPLANNER_REST_BASE>/timetables`

Minimal headers:

- `Accept: application/json`
- (Optional) `User-Agent: MetroTasMobile/<version>-<build> <platform>`

#### List available networks

Source: `assets/public/assets/useNetworks-B0EuGVHl.js`

```bash
curl '<TRIPPLANNER_REST_BASE>/networks' \
  -H 'Accept: application/json'
```

Response shape (simplified):

```json
{
  "items": [
    {
      "id": "hobart",
      "title": "City of Hobart",
      "type": "timetable",
      "record": {
        "id": "…",
        "network": { "id": "…", "title": "…" },
        "region":  { "id": "…", "title": "…" }
      }
    }
  ]
}
```

The app stores `networkId` and uses it to filter timetables.

#### List timetables for a network / region

Source: `assets/public/assets/index-DjBdTpM4.js`

- URL: `GET <TRIPPLANNER_REST_BASE>/timetables[?network_id=…&region_id=…]`

Parameters:

- `network_id` – network ID from `/networks`.
- `region_id` – region ID (optional).

```bash
# All timetables
curl '<TRIPPLANNER_REST_BASE>/timetables' \
  -H 'Accept: application/json'

# Filtered by network and region
curl '<TRIPPLANNER_REST_BASE>/timetables?network_id=<NETWORK_ID>&region_id=<REGION_ID>' \
  -H 'Accept: application/json'
```

Response (simplified):

```json
{
  "items": [
    {
      "id": "tt_hobart_1",
      "title": "Hobart Weekday Timetable",
      "routes": ["2", "10", "42"],
      "network": { "id": "hobart", "title": "City of Hobart" },
      "region":  { "id": "hobart", "title": "Hobart" }
    }
  ]
}
```

### GraphQL: Stops, Routes & Real‑time

The app uses Apollo Client against a GraphQL endpoint for stops, routes, trips and real‑time data.

Generic HTTP pattern:

```bash
curl '<TRIPPLANNER_GRAPHQL_ENDPOINT>' \
  -X POST \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-binary @body.json
```

Where `body.json` is:

```json
{
  "operationName": "SomeOperation",
  "variables": { /* per-query */ },
  "query": "…GraphQL query text…"
}
```

#### Stop‑level real‑time departures (`StopDetails`)

Sources:

- `assets/public/assets/_id_-BuC0k_Zl.js`
- `assets/public/assets/for-you-8ZzgyzFE.js`

Core query used for routes + real‑time stop departures:

```graphql
query StopDetails($id: ID!, $date: String!) {
  node(id: $id) {
    ... on Stop {
      routes {
        id
        gtfsId
        shortName
        longName
        color
        textColor
        mode
      }
      stoptimesForServiceDate(
        date: $date
        omitCanceled: true
        omitNonPickups: true
      ) {
        pattern {
          id
          route { gtfsId }
        }
        stoptimes {
          headsign
          scheduledDeparture
          realtime
          realtimeDeparture
          departureDelay
          trip {
            id
            gtfsId
          }
        }
      }
    }
  }
}
```

Variables:

- `id` – stop `id` (internal, not `gtfsId`).
- `date` – service date as `YYYY-MM-DD`.

Example body:

```json
{
  "operationName": "StopDetails",
  "variables": {
    "id": "<STOP_ID>",
    "date": "2024-11-22"
  },
  "query": "query StopDetails($id: ID!, $date: String!) { node(id: $id) { ... on Stop { routes { id gtfsId shortName longName color textColor mode } stoptimesForServiceDate(date: $date, omitCanceled: true, omitNonPickups: true) { pattern { id route { gtfsId } } stoptimes { headsign scheduledDeparture realtime realtimeDeparture departureDelay trip { id gtfsId } } } } } }"
}
```

`curl`:

```bash
curl '<TRIPPLANNER_GRAPHQL_ENDPOINT>' \
  -X POST \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-binary @body.json
```

Key real‑time fields per stoptime:

- `scheduledDeparture` – seconds since midnight (timetable).
- `realtimeDeparture` – seconds since midnight (live, if available).
- `realtime` – boolean flag for live data.
- `departureDelay` – delay in seconds.

#### Trip‑level real‑time & vehicle positions (`TripStoptimes`)

Source: `assets/public/assets/_id_-BdBSGlSF.js`

Fragments used:

```graphql
fragment RoutePartsExtra on Route {
  id
  gtfsId
  shortName
  longName
  color
  textColor
  mode
}

fragment TripPatternPartsWithStopRelationship on Pattern {
  id
  vehiclePositions {
    vehicleId
    label
    lat
    lon
    stopRelationship {
      status
      stop { id }
    }
    speed
    heading
    lastUpdated
    trip {
      id
      route { id }
    }
  }
}

fragment StopPartsFull on Stop {
  id
  gtfsId
  name
  code
  desc
  lat
  lon
  locationType
  url
}

fragment StoptimeParts on Stoptime {
  headsign
  scheduledDeparture
  realtime
  realtimeDeparture
  departureDelay
  stop { id }
}

fragment AlertParts on Alert {
  id
  alertHash
  alertUrl
  alertHeaderText
  alertDescriptionText
  alertCause
  alertEffect
  alertSeverityLevel
  effectiveEndDate
  effectiveStartDate
  entities {
    __typename
    ... on Route { gtfsId }
  }
}
```

Query:

```graphql
query TripStoptimes($id: ID!, $date: String!, $needsExtras: Boolean!) {
  node(id: $id) {
    ... on Trip {
      id
      gtfsId
      route { id }
      alerts { ...AlertParts }
      pattern {
        ...TripPatternPartsWithStopRelationship
      }
      stops {
        ...StopPartsFull
      }
      stoptimesForDate(serviceDate: $date) {
        stoptimes {
          ...StoptimeParts
        }
      }
      ...RoutePartsExtra @include(if: $needsExtras)
    }
  }
}
```

Variables:

- `id` – trip `id`.
- `date` – service date `YYYY-MM-DD`.
- `needsExtras` – `true` or `false` (whether you need extra route fields).

Example body:

```json
{
  "operationName": "TripStoptimes",
  "variables": {
    "id": "<TRIP_ID>",
    "date": "2024-11-22",
    "needsExtras": true
  },
  "query": "query TripStoptimes($id: ID!, $date: String!, $needsExtras: Boolean!) { node(id: $id) { ... on Trip { id gtfsId route { id } alerts { ...AlertParts } pattern { ...TripPatternPartsWithStopRelationship } stops { ...StopPartsFull } stoptimesForDate(serviceDate: $date) { stoptimes { ...StoptimeParts } } ...RoutePartsExtra @include(if: $needsExtras) } } } fragment RoutePartsExtra on Route { id gtfsId shortName longName color textColor mode } fragment TripPatternPartsWithStopRelationship on Pattern { id vehiclePositions { vehicleId label lat lon stopRelationship { status stop { id } } speed heading lastUpdated trip { id route { id } } } } fragment StopPartsFull on Stop { id gtfsId name code desc lat lon locationType url } fragment StoptimeParts on Stoptime { headsign scheduledDeparture realtime realtimeDeparture departureDelay stop { id } } fragment AlertParts on Alert { id alertHash alertUrl alertHeaderText alertDescriptionText alertCause alertEffect alertSeverityLevel effectiveEndDate effectiveStartDate entities { __typename ... on Route { gtfsId } } }"
}
```

`curl`:

```bash
curl '<TRIPPLANNER_GRAPHQL_ENDPOINT>' \
  -X POST \
  -H 'Content-Type: application/json' \
  -H 'Accept: application/json' \
  --data-binary @body.json
```

Key real‑time pieces:

- `pattern.vehiclePositions[]` – live vehicles (lat/lon, speed, heading, `lastUpdated`, stop relationship).
- `stoptimesForDate.stoptimes[]` – trip timetable with real‑time adjustments (same fields as `StopDetails`).

### Discovering the real base URLs

Because the compiled JS only uses abstract constants, the actual hosts for `<TRIPPLANNER_REST_BASE>` and `<TRIPPLANNER_GRAPHQL_ENDPOINT>` are not embedded in `assets/public/assets`. To discover them:

1. Install and run the production app.
2. Configure a proxy (Charles, mitmproxy, etc.).
3. Capture requests to `/networks`, `/timetables`, and the GraphQL endpoint.
4. Replace the placeholders in the `curl` examples above with the captured URLs.

