// The reviews Web App: product reviews, kept in memory.
//
//   GET  /reviews?productId=mug   the reviews of one product, or all of them
//   POST /reviews                 adds one: {"productId": "mug", "rating": 5, "text": "..."}
//
// It answers only requests carrying the x-api-key that API Management adds
// from its backend's credentials (see 5-api-management.tf), so it can't be
// called around the gateway. It has no dependencies, so there's nothing to
// install before deploying it.
"use strict";

const http = require("node:http");

const apiKey = process.env.API_KEY || "";
const port = Number(process.env.PORT || 8080);
const reviews = [
  { productId: "mug", rating: 5, text: "Holds tea. Recommended." },
  { productId: "tote", rating: 4, text: "Carries the shopping, folds away small." },
];

function send(res, status, body) {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(body));
}

http.createServer((req, res) => {
  // Set by API Management on the requests it forwards, so the response shows
  // which way the request came in.
  const via = req.headers["x-forwarded-by"] || "direct";
  if (!apiKey || req.headers["x-api-key"] !== apiKey) {
    return send(res, 401, { error: "missing or wrong x-api-key", via });
  }

  const url = new URL(req.url, "http://localhost");
  if (url.pathname !== "/reviews") {
    return send(res, 404, { error: "not found" });
  }

  if (req.method === "GET") {
    const id = url.searchParams.get("productId");
    return send(res, 200, { app: "reviews", via, reviews: id ? reviews.filter((r) => r.productId === id) : reviews });
  }

  if (req.method === "POST") {
    let raw = "";
    req.on("data", (chunk) => (raw += chunk));
    req.on("end", () => {
      let r;
      try {
        r = JSON.parse(raw);
      } catch {
        return send(res, 400, { error: "the body must be JSON" });
      }
      if (!r.productId || !(r.rating >= 1 && r.rating <= 5)) {
        return send(res, 400, { error: "productId and a rating from 1 to 5 are required" });
      }
      const review = { productId: String(r.productId), rating: Number(r.rating), text: String(r.text || "") };
      reviews.push(review);
      send(res, 201, { app: "reviews", via, review });
    });
    return;
  }

  send(res, 405, { error: "method not allowed" });
}).listen(port, () => console.log(`reviews listening on ${port}`));
