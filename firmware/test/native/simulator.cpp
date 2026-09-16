#include "protocol.hpp"
#include <fstream>
#include <iomanip>
#include <iostream>
#include <openssl/evp.h>
#include <openssl/pem.h>
#include <openssl/rand.h>
#include <sstream>
using namespace airobot;
std::string read(const std::string &p) {
  std::ifstream f(p);
  std::stringstream s;
  s << f.rdbuf();
  return s.str();
}
std::string hash(const std::string &s) {
  unsigned char digest[32];
  unsigned n = 0;
  EVP_Digest(s.data(), s.size(), digest, &n, EVP_sha256(), nullptr);
  std::ostringstream out;
  for (int i = 0; i < 32; i++)
    out << std::hex << std::setw(2) << std::setfill('0') << int(digest[i]);
  return out.str();
}
std::string randomId() {
  unsigned char data[16];
  RAND_bytes(data, 16);
  std::ostringstream s;
  for (int i = 0; i < 16; i++)
    s << std::hex << std::setw(2) << std::setfill('0') << int(data[i]);
  return s.str();
}
std::string decode(std::string s) {
  std::replace(s.begin(), s.end(), '-', '+');
  std::replace(s.begin(), s.end(), '_', '/');
  while (s.size() % 4)
    s += '=';
  std::string out(s.size(), '\0');
  int n = EVP_DecodeBlock(reinterpret_cast<unsigned char *>(&out[0]),
                          reinterpret_cast<const unsigned char *>(s.data()),
                          s.size());
  if (n < 0)
    return "";
  if (!s.empty() && s.back() == '=')
    n--;
  if (s.size() > 1 && s[s.size() - 2] == '=')
    n--;
  out.resize(n);
  return out;
}
int main(int argc, char **argv) {
  if (argc != 5) {
    std::cerr << "Usage: simulator ROBOT_ID PROFILE_JSON PUBLIC_KEY "
                 "STATE_DIRECTORY\n";
    return 1;
  }
  Runtime r(argv[1], randomId());
  std::string dir = argv[4];
  r.sha = hash;
  r.random = randomId;
  r.persist = [&](const std::string &key, const std::string &body) {
    std::ofstream f(dir + "/" + key + ".tmp");
    f << body;
    f.close();
    return !f.fail() && !std::rename((dir + "/" + key + ".tmp").c_str(),
                                     (dir + "/" + key).c_str());
  };
  std::string publicKey = read(argv[3]);
  r.verify = [&](const std::string &token, Json &claims) {
    size_t a = token.find('.'), b = token.find('.', a + 1);
    if (a == std::string::npos || b == std::string::npos)
      return false;
    Json header;
    if (deserializeJson(header, decode(token.substr(0, a))) ||
        header["alg"] != "RS256")
      return false;
    auto sig = decode(token.substr(b + 1));
    BIO *bio = BIO_new_mem_buf(publicKey.data(), publicKey.size());
    EVP_PKEY *key = PEM_read_bio_PUBKEY(bio, nullptr, nullptr, nullptr);
    BIO_free(bio);
    if (!key)
      return false;
    EVP_MD_CTX *ctx = EVP_MD_CTX_new();
    bool ok =
        EVP_DigestVerifyInit(ctx, nullptr, EVP_sha256(), nullptr, key) == 1 &&
        EVP_DigestVerify(
            ctx, reinterpret_cast<const unsigned char *>(sig.data()),
            sig.size(), reinterpret_cast<const unsigned char *>(token.data()),
            b) == 1;
    EVP_MD_CTX_free(ctx);
    EVP_PKEY_free(key);
    return ok &&
           !deserializeJson(claims, decode(token.substr(a + 1, b - a - 1)));
  };
  auto body = read(dir + "/profile");
  if (body.empty())
    body = read(argv[2]);
  Json p;
  Profile profile;
  profile.hash = hash(body);
  if (deserializeJson(p, body) || !parseProfile(p, profile)) {
    std::cerr << "Invalid simulation profile\n";
    return 2;
  }
  r.core.configure(profile);
  r.profileJson = body;
  auto latch = read(dir + "/latch");
  if (!latch.empty()) {
    r.core.latch();
    r.latchId = latch;
    r.resetNonce = randomId();
  }
  auto emit = [&](const char *topic, Json &value) {
    Json out;
    out["topic"] = topic;
    out["payload"] = value;
    serializeJson(out, std::cout);
    std::cout << std::endl;
  };
  auto state = r.status();
  emit("state", state);
  std::string line;
  while (std::getline(std::cin, line)) {
    Json in;
    if (deserializeJson(in, line))
      continue;
    uint64_t mono = in["monoMs"], epoch = in["epochMs"];
    if (in["kind"] == "tick") {
      bool online = in["connected"];
      bool control = online && !r.session.empty() && r.sessionExpiry > epoch;
      r.core.tick(mono, control);
      if (!control &&
          (r.core.state == State::STOPPING || r.core.state == State::HOLD))
        r.invalidate();
    } else {
      std::string raw = in["raw"];
      auto ack = r.handle(raw, in["retained"] | false, epoch, mono,
                          in["emergency"] | false);
      emit("ack", ack);
    }
    Json lifecycle;
    if (r.lifecycle(lifecycle))
      emit("ack", lifecycle);
    state = r.status();
    emit("state", state);
  }
}
