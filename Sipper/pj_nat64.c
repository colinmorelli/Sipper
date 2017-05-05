//
//  pj_nat64.c
//  Sipper
//
//  Created by Colin Morelli on 11/4/16.
//  Copyright © 2016 Sipper. All rights reserved.
//

#include "pj_nat64.h"

#include <pjsua.h>
#include <pjnath.h>
#include <pjsua-lib/pjsua_internal.h>

#define THIS_FILE "pj_nat64.c"

static nat64_options module_options;

struct ice_candidate {
  int length;
  char *foundation;
  char *component;
  char *transport;
  int priority;
  char *host;
  char *port;
  char *type;
};

/* Syntax error handler for parser. */
static void on_syntax_error(pj_scanner *scanner)
{
  PJ_UNUSED_ARG(scanner);
  PJ_LOG(4, (THIS_FILE, "Scanner syntax error at %s", scanner->curptr));
  PJ_THROW(PJ_EINVAL);
  
}

//Helper that will resolve or synthesize to ipv6. Output buffer will be null terminated
static pj_bool_t resolve_or_synthesize_ipv4_to_ipv6(pj_str_t* host_or_ip, char* buf, int buf_len)
{
  unsigned int count = 1;
  pj_addrinfo ai[1];
  pj_getaddrinfo(PJ_AF_UNSPEC, host_or_ip, &count, ai);
  
  if (count > 0) {
    if (ai[0].ai_addr.addr.sa_family == PJ_AF_INET) {
      return pj_inet_ntop(PJ_AF_INET, &ai[0].ai_addr.ipv4.sin_addr, buf, PJ_INET_ADDRSTRLEN) == PJ_SUCCESS;
    } else if (ai[0].ai_addr.addr.sa_family == PJ_AF_INET6) {
      return pj_inet_ntop(PJ_AF_INET6, &ai[0].ai_addr.ipv6.sin6_addr, buf,
                   PJ_INET6_ADDRSTRLEN) == PJ_SUCCESS;
    } else {
      return PJ_FALSE;
    }
  } else {
    return PJ_FALSE;
  }
  
  return PJ_TRUE;
}

static pj_status_t synthesize_ipv6_default_address(pj_pool_t *pool, char *org_buffer, char *new_buffer)
{
  PJ_USE_EXCEPTION;
  pj_status_t status;
  pj_scanner scanner;
  char *walker_p = new_buffer;
  pj_str_t result = {NULL, 0};
  
  pj_scan_init(&scanner, org_buffer, strlen(org_buffer), 0, &on_syntax_error);
  
  PJ_TRY {
    do {
      
      // Search for IP4 media addresses
      pj_scan_get_until_chr(&scanner, "Ii", &result);
      pj_memcpy(walker_p, result.ptr, result.slen);
      walker_p = walker_p + result.slen;
      
      // Make sure there's still more to read
      if (pj_scan_is_eof(&scanner)) {
        break;
      }

      // Find the IP address (read until end of line)
      pj_scan_get_until_chr(&scanner, "\r\n", &result);
      
      // We found an IP4 address, synthsize and return
      if (pj_strnicmp2(&result, "IP4 ", 4) == 0) {
        pj_str_t resolvable;
        pj_strdup(pool, &resolvable, &result);
        pj_strset(&resolvable, resolvable.ptr + 4, resolvable.slen - 4);
        PJ_LOG(5, (THIS_FILE, "Found IPv4 media address '%.*s'", resolvable.slen, resolvable.ptr));
        
        // Attempt to resolve the IPv6 address
        char resolved[PJ_INET6_ADDRSTRLEN];
        if (resolve_or_synthesize_ipv4_to_ipv6(&resolvable, resolved, PJ_INET6_ADDRSTRLEN) == PJ_FALSE) {
          PJ_LOG(3, (THIS_FILE, "Failed to synthesize IPv6 address for IPv4 literal '%.*s', leaving in-tact", result.slen, result.ptr));
          
          // Couldn't find an IPv6 replacement, so just keep the original match
          pj_memcpy(walker_p, result.ptr, result.slen);
          walker_p = walker_p + result.slen;
        } else {
          PJ_LOG(5, (THIS_FILE, "Synthesized IPv6 address '%s' for IPv4 literal '%.*s'", resolved, result.slen, result.ptr));
          
          // Push the new match into the buffer
          char replacement[PJ_INET6_ADDRSTRLEN + 4];
          int length = pj_ansi_snprintf(replacement, PJ_INET6_ADDRSTRLEN + 4, "IP6 %s", resolved);
          pj_memcpy(walker_p, replacement, length);
          walker_p = walker_p + length;
        }
      } else {
        
        // Not an IP address, tack back on to the end of the buffer and keep going
        pj_memcpy(walker_p, result.ptr, result.slen);
        walker_p = walker_p + result.slen;
      }
      
    } while(!pj_scan_is_eof(&scanner));
    
    // Made it through the string with no parse errors
    status = PJ_SUCCESS;
  } PJ_CATCH_ANY {
    status = PJ_EINVAL;
  }
  
  PJ_END;
  pj_scan_fini(&scanner);
  return status;
}


static pj_bool_t replace_ipv4_with_ipv6(pj_pool_t *pool, pjmedia_sdp_conn *conn)
{
  char resolved[PJ_INET6_ADDRSTRLEN];
  
  if (resolve_or_synthesize_ipv4_to_ipv6(&conn->addr, resolved, PJ_INET6_ADDRSTRLEN)) {
    int resolved_length = (int) strlen(resolved);
    PJ_LOG(5, (THIS_FILE, "Replacing IPv4 address '%.*s' with synthesized IPv6 address '%.*s' in media connection line",
               conn->addr.slen, conn->addr.ptr, resolved_length, resolved));
    
    conn->addr_type = pj_strdup3(pool, "IP6");
    conn->addr = pj_strdup3(pool, resolved);
    return PJ_TRUE;
  } else {
    return PJ_FALSE;
  }
}

static pj_status_t synthesize_ipv6_for_connection_addresses(pj_pool_t *pool, pjmedia_sdp_session *session)
{
  if (session->conn) {
    pjmedia_sdp_conn *conn = session->conn;
    if (pj_stricmp2(&conn->addr_type, "IP4") == 0) {
      replace_ipv4_with_ipv6(pool, conn);
    }
  }
  
  for (int i = 0; i < session->media_count; i++) {
    pjmedia_sdp_media *media = session->media[i];
    if (media->conn) {
      pjmedia_sdp_conn *conn = media->conn;
      if (pj_stricmp2(&conn->addr_type, "IP4") == 0) {
        replace_ipv4_with_ipv6(pool, conn);
      }
    }
  }
  
  return PJ_SUCCESS;
}

static pj_status_t append_synthesized_ice_candidates(pj_pool_t *pool, pjmedia_sdp_session *session)
{
  
  // Find all candidate attributes in the SDP and create temporary synthesized IPv6 records for them
  for (int i = 0; i < session->media_count; i++) {
    struct ice_candidate candidates[PJMEDIA_MAX_SDP_ATTR];
    int candidates_cnt = 0;
    pjmedia_sdp_media *media = session->media[i];
    for (int j = 0; j < media->attr_count; j++) {
      pjmedia_sdp_attr *attr = media->attr[j];
      if (pj_stricmp2(&attr->name, "candidate") == 0) {
        pj_str_t value;
        pj_strdup_with_null(pool, &value, &attr->value);
        struct ice_candidate candidate;
        
        // Attempt to "parse" the candidate
        char *foundation = strtok(value.ptr, " ");
        char *component = strtok(NULL, " ");
        char *transport = strtok(NULL, " ");
        char *priority = strtok(NULL, " ");
        char *host = strtok(NULL, " ");
        char *port = strtok(NULL, " ");
        char *type = strtok(NULL, "");
        if (!foundation || !component || !transport || !port || !priority || !host || !type) {
          continue;
        }
        
        // If it's already an IPv6 candidate, bail here - we're not going to synthesize any
        // IPv6 addresses if we already have some in the set
        if (pj_ansi_strchr(host, ':')) {
          break;
        }
        
        // Create a new candidate record for this - we'll synthesize in the next step
        candidate.length = (int) value.slen;
        candidate.foundation = foundation;
        candidate.component = component;
        candidate.transport = transport;
        candidate.priority = atoi(priority);
        candidate.port = port;
        candidate.host = host;
        candidate.type = type;
        candidates[candidates_cnt++] = candidate;
      }
    }
    
    // Append synthesized records to the end as long as we have space
    for (int i = 0; i < candidates_cnt && media->attr_count < PJMEDIA_MAX_SDP_ATTR; i++) {
      struct ice_candidate candidate = candidates[i];
      pj_str_t host = pj_str(candidate.host);
      char resolved[PJ_INET6_ADDRSTRLEN];
      if (resolve_or_synthesize_ipv4_to_ipv6(&host, resolved, PJ_INET6_ADDRSTRLEN)) {
        int adjusted_length = (int) candidate.length + (int) (strlen(resolved) - host.slen) + 1;
        char output[adjusted_length];
        pj_ansi_snprintf(output, adjusted_length, "%s %s %s %d %s %s %s", candidate.foundation, candidate.component,
                         candidate.transport, candidate.priority + 1, resolved, candidate.port, candidate.type);
        
        pj_str_t result = pj_str(output);
        pjmedia_sdp_attr *attr = pjmedia_sdp_attr_create(pool, "candidate", &result);
        media->attr[media->attr_count++] = attr;
        
        PJ_LOG(5, (THIS_FILE, "Appending SDP attribute for synthesized IPv6 ICE candidate: %.*s",
                   attr->value.slen, attr->value.ptr));
      }
    }
  }
  
  return PJ_SUCCESS;
}

pj_status_t append_ipv4_ice_candidate(pj_pool_t *pool, pjmedia_sdp_session *session)
{
  
  // Find all candidate attributes in the SDP and create temporary synthesized IPv6 records for them
  for (int i = 0; i < session->media_count; i++) {
    struct ice_candidate candidate;
    pjmedia_sdp_media *media = session->media[i];
    pj_bool_t candidate_found = PJ_FALSE;
    
    for (int j = 0; j < media->attr_count; j++) {
      pjmedia_sdp_attr *attr = media->attr[j];
      if (pj_stricmp2(&attr->name, "candidate") == 0) {
        pj_str_t value;
        pj_strdup_with_null(pool, &value, &attr->value);
        
        // Attempt to "parse" the candidate
        char *foundation = strtok(value.ptr, " ");
        char *component = strtok(NULL, " ");
        char *transport = strtok(NULL, " ");
        char *priority = strtok(NULL, " ");
        char *host = strtok(NULL, " ");
        char *port = strtok(NULL, " ");
        char *type = strtok(NULL, "");
        if (!foundation || !component || !transport || !port || !priority || !host || !type) {
          continue;
        }
        
        // Calculate the priority for the candidate
        int priority_val = atoi(priority);
        
        // Create a new candidate record for this if we don't have any candidates
        if (!candidate_found || priority_val < candidate.priority) {
          candidate.length = (int) value.slen;
          candidate.foundation = foundation;
          candidate.component = component;
          candidate.transport = transport;
          candidate.priority = priority_val;
          candidate.port = port;
          candidate.host = host;
          candidate.type = type;
          candidate_found = PJ_TRUE;
        }
      }
    }
    
    // Append synthesized records to the end as long as we have space
    if (media->attr_count < PJMEDIA_MAX_SDP_ATTR && candidate_found) {
      pj_str_t host = pj_str("169.254.169.254");
      int adjusted_length = (int) candidate.length + (int) (host.slen - strlen(candidate.host)) + 1;
      char output[adjusted_length];
      pj_ansi_snprintf(output, adjusted_length, "%s %s %s %d %.*s %s %s", candidate.foundation, candidate.component,
                       candidate.transport, candidate.priority - 1, (int) host.slen, host.ptr, candidate.port, candidate.type);
      
      pj_str_t result = pj_str(output);
      pjmedia_sdp_attr *attr = pjmedia_sdp_attr_create(pool, "candidate", &result);
      media->attr[media->attr_count++] = attr;
      
      PJ_LOG(5, (THIS_FILE, "Appending SDP attribute for fake IPv4 candidate: %.*s",
                 attr->value.slen, attr->value.ptr));
    }
  }
  
  return PJ_SUCCESS;
}

static pj_status_t replace_message_body(char *original, char *body_start, char *body, int length)
{
  // Calculate the length of the header portion, we're going to scan through this
  int header_length = (int) strlen(original) - (int) strlen(body_start);
  
  // Avoid buffer overflows, make sure we're within the packet size
  int complete_length = (int) header_length + 4 + length;
  if (complete_length >= PJSIP_MAX_PKT_LEN) {
    PJ_LOG(3, (THIS_FILE, "New body content pushes packet length to %d, but buffer size is %d", complete_length, PJSIP_MAX_PKT_LEN));
    return PJ_ENOMEM;
  }
  
  // Overwrite back onto the original
  pj_memcpy(body_start, body, length);
  original[complete_length] = '\0';
  
  return PJ_SUCCESS;
}

static pj_status_t ipv6_mod_on_rx(pjsip_rx_data *rdata)
{
  pjsip_media_type app_sdp;
  pjsip_cseq_hdr *cseq = rdata->msg_info.cseq;
  pjsip_ctype_hdr *ctype = rdata->msg_info.ctype;
  pjsip_transport_type_e transport_type = rdata->tp_info.transport->factory->type;
  pjsip_media_type_init2(&app_sdp, "application", "sdp");
  pjsip_msg *msg = rdata->msg_info.msg;
  
  if (cseq != NULL && cseq->method.id == PJSIP_INVITE_METHOD && (transport_type & PJSIP_TRANSPORT_IPV6) == PJSIP_TRANSPORT_IPV6) {
    if (ctype && msg && msg->body && pj_stricmp(&ctype->media.type, &app_sdp.type) == 0 && pj_stricmp(&ctype->media.subtype, &app_sdp.subtype) == 0) {
      PJ_LOG(4, (THIS_FILE, "Received incoming response to INVITE via IPv6, synthesizing IPv6 addresses from IPv4 candidates in SDP"));
      PJ_LOG(5, (THIS_FILE, "Printing packet before mangling SDP: %.*s", rdata->msg_info.len, rdata->msg_info.msg_buf));
      char *buffer = rdata->msg_info.msg_buf;
      
      // Find the start of the body in the original message
      char *body_delim = "\r\n\r\n";
      char *body_start = strstr(buffer, body_delim);
      
      // If we can't find the body delimeter, bail out here
      if (!body_start) {
        return PJ_SUCCESS;
      }
      
      // Parse the incoming SDP - since we need to make multiple passes over it anyway this isn't much worse (if at all)
      // than scanning through the string
      int body_len = (int) strlen(body_start) - 4;
      pjmedia_sdp_session *sdp;
      pj_status_t status = pjmedia_sdp_parse(rdata->tp_info.pool, body_start + 4, body_len, &sdp);
      if (status != PJ_SUCCESS) {
        PJ_LOG(4, (THIS_FILE, "Failed to parse SDP, leaving message in-tact and continuing"));
        return PJ_SUCCESS;
      }
      
      // Update the default media IP address to an IPv6 variant
      status = synthesize_ipv6_for_connection_addresses(rdata->tp_info.pool, sdp);
      if (status != PJ_SUCCESS) {
        PJ_LOG(3, (THIS_FILE, "Error encountered while synthesizing IPv6 default media addresses, leaving original message in-tact"));
        return PJ_SUCCESS;
      }
      
      // Attempt to synthesize IPv6 addresses for IPv4 ICE candidates
      status = append_synthesized_ice_candidates(rdata->tp_info.pool, sdp);
      if (status != PJ_SUCCESS) {
        PJ_LOG(3, (THIS_FILE, "Error encountered while synthesizing IPv6 ICE candidates, leaving original message in-tact"));
        return PJ_SUCCESS;
      }
      
      // Copy back over the original buffer so pjsip is aware of the new message
      char replaced_buffer[PJSIP_MAX_PKT_LEN];
      int length = pjmedia_sdp_print(sdp, replaced_buffer, PJSIP_MAX_PKT_LEN);
      
      // Replace the original buffer with the new SDP content
      status = replace_message_body(buffer, body_start + 4, replaced_buffer, length);
      if (status != PJ_SUCCESS) {
        PJ_LOG(3, (THIS_FILE, "Failed to rewrite packet with new SDP, leaving original message in-tact"));
        return PJ_SUCCESS;
      }
      
      PJ_LOG(5, (THIS_FILE, "Reconstructed packet with new SDP: %s", buffer));
      
      // Update all internal packet sizes
      pjsip_clen_hdr *clen = pjsip_clen_hdr_create(rdata->tp_info.pool);
      clen->len = length;
      
      rdata->msg_info.clen = clen;
      rdata->msg_info.msg->body->len = length;
      rdata->pkt_info.len = strlen(rdata->pkt_info.packet);
      rdata->msg_info.len = (int)rdata->pkt_info.len;
      rdata->tp_info.transport->last_recv_len = rdata->pkt_info.len;
    }
  }
  
  return PJ_SUCCESS;
}

pj_status_t ipv6_mod_on_tx(pjsip_tx_data *tdata)
{
  pjsip_media_type app_sdp;
  pjsip_transport_type_e transport_type = tdata->tp_info.transport->factory->type;
  pjsip_media_type_init2(&app_sdp, "application", "sdp");
  pjsip_msg *msg = tdata->msg;
  
  if (tdata->msg->body != NULL && tdata->msg->line.req.method.id == PJSIP_INVITE_METHOD) {
    pjsip_media_type media_type = tdata->msg->body->content_type;
    
    // If this is an SDP...
    if (pjsip_media_type_cmp(&app_sdp, &media_type, 0) == 0) {
      PJ_LOG(3, (THIS_FILE, "Detected outgoing INVITE with SDP, adding fake IPv4 candidate to list"));
      pjmedia_sdp_session *sdp = (pjmedia_sdp_session *) msg->body->data;
      pjmedia_sdp_session *cloned = pjmedia_sdp_session_clone(tdata->pool, sdp);

      // Attempt to synthesize IPv6 addresses for IPv4 ICE candidates
      pj_status_t status = append_ipv4_ice_candidate(tdata->pool, cloned);
      if (status != PJ_SUCCESS) {
        PJ_LOG(3, (THIS_FILE, "Error encountered while creating fake IPv4 candidate, leaving original message in-tact"));
        return PJ_SUCCESS;
      }
      
      // Copy back over the original buffer so pjsip is aware of the new message
      msg->body->data = cloned;
      pjsip_tx_data_invalidate_msg(tdata);
      status = pjsip_tx_data_encode(tdata);
      if (status != PJ_SUCCESS) {
        PJ_LOG(3, (THIS_FILE, "Error encountered while encoding SIP message in the TX data"));
        return PJ_SUCCESS;
      }
    }
  }
  
  return PJ_SUCCESS;
}

/* L1 rewrite module for sdp info.*/
static pjsip_module ipv6_module = {
  NULL, NULL,                     /* prev, next.      */
  { "mod-ipv6", 8},               /* Name.            */
  -1,                             /* Id               */
  0,                              /* Priority         */
  NULL,                           /* load()           */
  NULL,                           /* start()          */
  NULL,                           /* stop()           */
  NULL,                           /* unload()         */
  &ipv6_mod_on_rx,                /* on_rx_request()  */
  &ipv6_mod_on_rx,                /* on_rx_response() */
  &ipv6_mod_on_tx,                /* on_tx_request.   */
  &ipv6_mod_on_tx,                /* on_tx_response() */
  NULL,                           /* on_tsx_state()   */
};

pj_status_t pj_nat64_enable_rewrite_module()
{
  module_options = 0;
  
  return pjsip_endpt_register_module(pjsua_get_pjsip_endpt(), &ipv6_module);
}

pj_status_t pj_nat64_disable_rewrite_module()
{
  return pjsip_endpt_unregister_module( pjsua_get_pjsip_endpt(),
                                       &ipv6_module);
}

void pj_nat64_set_options(nat64_options options)
{
  module_options = options;
}
