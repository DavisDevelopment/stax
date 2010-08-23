/*
 HaXe library written by John A. De Goes <john@socialmedia.com>
 Contributed by Social Media Networks

 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:

 Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.
 Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the
 distribution.

 THIS SOFTWARE IS PROVIDED BY SOCIAL MEDIA NETWORKS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS
 FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL SOCIAL MEDIA NETWORKS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN
 CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
*/
package js.io;

import Dom;
import Prelude;

import js.Env;
import js.dom.Quirks;
import haxe.data.collections.List;
import haxe.data.collections.Map;
import haxe.time.ScheduledExecutor;
import haxe.text.json.Json;
import haxe.net.Url;
import haxe.io.log.Logger;

using PreludeExtensions;
using haxe.functional.FoldableExtensions;
using haxe.util.StringExtensions;
using haxe.data.collections.IterableExtensions;
using haxe.net.UrlExtensions;
using haxe.framework.Injector;

/** A bidirectional communication layer capable of crossing frames hosted on 
 * different domains.
 */
interface IFrameIO {
  /** Adds a receiver that will handle messages from the given domain.
   *
   * @param f             The function that will be passed each message.
   *
   * @param originUrl     The URL where the messages will come from, including 
   *                      the query string but without the hash tag.
   *
   * @param originWindow  The window that the messages will come from. If this
   *                      parameter is not specified, reliable reception from
   *                      the origin window is not possible.
   */
  public function receive(f: Dynamic -> Void, originUrl: String, ?originWindow: Window): IFrameIO;

  /** Adds a receiver that will handle messages from the given domain for as 
   * long as it returns true.
   *
   * @param f             The function that will be passed each message.
   *
   * @param originUrl     The URL where the messages will come from, including 
   *                      the query string but without the hash tag.
   *
   * @param originWindow  The window that the messages will come from. If this
   *                      parameter is not specified, reliable reception from
   *                      the origin window is not possible.
   */
  public function receiveWhile(f: Dynamic -> Bool, originUrl: String, ?originWindow: Window): IFrameIO;
  
  /** Receives and responds to requests with the specified function.
   *
   * @param f       The function that will receive and responde to requests.
   *
   * @param url     The URL of the target/source window, including the query string but without the hash tag. 
   *
   * @param window  The window of the target/source window.
   */
  public function receiveRequests(f: Dynamic -> Future<Dynamic>, url: String, window: Window): IFrameIO;

  /** Posts a message to the specified iframe, which should be located at the 
   * exact URL specified.
   *
   * @param data          The anonymous object that will be sent.
   *
   * @param targetUrl     The exact URL the message is being sent to, including 
   *                      host, port, path, and query, but excluding hash tag.
   *
   * @param targetWindow  The window that will receive the message.
   */
  public function send(data: Dynamic, targetUrl: String, targetWindow: Window): IFrameIO;
  
  /** Sends a request for information to the specified iframe, which should be
   * located at the exact URL specified.
    *
    * @param request       The anonymous object that will be sent.
    *
    * @param targetUrl     The exact URL the message is being sent to, including 
    *                      host, port, path, and query, but excluding hash tag.
    *
    * @param targetWindow  The window that will receive the message.
    *
    */
  public function request(request: Dynamic, targetUrl: String, targetWindow: Window): Future<Dynamic>;
}

private class AbstractIFrameIO implements IFrameIO {
  var requestCounter: Int;
  
  public function new() {
    requestCounter = 0;
  }
  
  public function receive(f: Dynamic -> Void, originUrl: String, ?originWindow: Window): IFrameIO {
    return Stax.error('Not implemented');
  }

  public function receiveWhile(f: Dynamic -> Bool, originUrl: String, ?originWindow: Window): IFrameIO {
    return Stax.error('Not implemented');
  }
  
  public function receiveRequests(f: Dynamic -> Future<Dynamic>, url, window: Window): IFrameIO {
    var self = this;
    
    return receive(function(request) {
      if (request.__requestId != null) {
        var response = f(request);
        
        response.deliverTo(function(response) {
          response.__responseId = request.__requestId;

          self.send(response, url, window);
        });
      }
    }, url, window);
  }

  public function send(data: Dynamic, targetUrl: String, targetWindow: Window): IFrameIO {
    return Stax.error('Not implemented');
  }
  
  public function request(request: Dynamic, targetUrl: String, targetWindow: Window): Future<Dynamic> {
    var requestId = ++requestCounter;
    
    var future: Future<Dynamic> = new Future();
    
    request.__requestId = requestId;
    
    send(request, targetUrl, targetWindow);
    
    receiveWhile(function(data) {
      return if (data.__responseId != null && data.__responseId == requestId) {
        future.deliver(data);
        
        false;
      }
      else true;
    }, targetUrl, targetWindow);
    
    return future;
  }
}

class IFrameIOAutoDetect implements IFrameIO {
  var bindTarget: Window;
  var underlying: IFrameIO;
  
  public function new(?w: Window) {
    this.bindTarget = w.toOption().getOrElseC(Env.window);    
    this.underlying = if (bindTarget.postMessage != null) cast(new IFrameIOPostMessage(bindTarget), IFrameIO); 
                      else cast(new IFrameIOPollingHashtag(bindTarget), IFrameIO);
  }
  
  public function receive(f: Dynamic -> Void, originUrl: String, ?originWindow: Window): IFrameIO {
    underlying.receive(f, originUrl, originWindow);
    
    return this;
  }

  public function receiveWhile(f: Dynamic -> Bool, originUrl: String, ?originWindow: Window): IFrameIO {
    underlying.receiveWhile(f, originUrl, originWindow);
    
    return this;
  }
  
  public function receiveRequests(f: Dynamic -> Future<Dynamic>, url, window: Window): IFrameIO {
    underlying.receiveRequests(f, url, window);
    
    return this;
  }

  public function send(data: Dynamic, targetUrl: String, targetWindow: Window): IFrameIO {
    underlying.send(data, targetUrl, targetWindow);
    
    return this;
  }  
  
  public function request(data: Dynamic, targetUrl: String, targetWindow: Window): Future<Dynamic> {
    return underlying.request(data, targetUrl, targetWindow);
  }
}

class IFrameIOPostMessage extends AbstractIFrameIO, implements IFrameIO {
  var bindTarget: Window;
  
  static var log = Logger.debug();
  
  public function new(w: Window) {
    super();
    
    this.bindTarget = w;
  }
  
  override public function receive(f: Dynamic -> Void, originUrl: String, ?originWindow: Window): IFrameIO {
    return receiveWhile(function(d) return true.withEffect(function(_) { f(d); }), originUrl, originWindow);
  }

  override public function receiveWhile(f: Dynamic -> Bool, originUrl_: String, ?originWindow: Window): IFrameIO {
    var originUrl = getUrlFor(originWindow, originUrl_);
    
    log.debug('originUrl = ' + originUrl + ', originUrl_ = ' + originUrl_);

    var listener: EventListener<Dynamic> = null;
    
    var self = this;
    
    listener = function(event) {
      if (event.origin == originUrl || event.origin == 'null') {
        var data = Json.decodeObject(event.data);
        
        if (!f(data)) {
          Quirks.removeEventListener(self.bindTarget, 'message', listener, false);
        }
      }
    }
    
    Quirks.addEventListener(bindTarget, 'message', listener, false);
    
    return this;
  }

  override public function send(data: Dynamic, targetUrl_: String, targetWindow: Window): IFrameIO {
    var targetUrl = getUrlFor(targetWindow, targetUrl_);
    
    if (targetUrl.startsWith('file:')) targetUrl = '*';
    
    targetWindow.postMessage(Json.encodeObject(data), targetUrl);
    
    return this;
  }
  
  private static function normalizeOpt(url: Url): Option<Url> {
    log.debug('normalizeOpt url = ' + url);
    
    return url.toParsedUrl().map(function(p) return p.withoutHash().withoutPathname().withoutSearch().toUrl());
  }
  
  private static function normalize(url: Url): Url {
    return normalizeOpt(url).getOrElseC(url);
  }
  
  private static function getUrlFor(w: Window, url_: Url): Url {
    // TODO: Cleanup!!!
    var tryExtractUrl = function(w: Window): Url {
      return normalizeOpt(url_).getOrElse(
        function() {
          try {
            return normalize(w.location.href);
          }
          catch (d: Dynamic) {
            return url_;
          }
        }
      );
    }
    
    var cur = w;
    
    while (cur != null) {
      var url = tryExtractUrl(cur);
      
      if (!url.startsWith('about:')) {
        return normalize(url);
      }
      
      if (cur == cur.top) cur = null;
      else cur = cur.parent;
    }
    
    return url_;
  }
}


class IFrameIOPollingHashtag extends AbstractIFrameIO, implements IFrameIO {
  static var lastMessageId = 1;
  static var newFragmentsList = List.factory();
  
  var executor:           ScheduledExecutor;
  var fragmentsToSend:    List<Tuple2<Window, AddressableFragment>>;
  var fragmentsReceived:  Map<MessageKey, Array<FragmentDelivery>>;
  var receivers:          Hash<Array<Dynamic -> Void>>;
  var originUrlToWindow:  Hash<Window>;
  var bindTarget:         Window;
  var senderFuture:       Option<Future<Void>>;
  var receiverFuture:     Option<Future<Void>>;
  
	public function new(w: Window) {
	  super();
	  
	  this.bindTarget         = w;
		this.executor           = ScheduledExecutor.inject();
		this.fragmentsToSend    = newFragmentsList();
		this.fragmentsReceived  = Map.create(MessageKey.HasherT(), MessageKey.EqualT());
		this.receivers          = new Hash();
		this.originUrlToWindow  = new Hash();
		
		senderFuture   = None;
		receiverFuture = None;
	}
	
	override public function receive(f: Dynamic -> Void, originUrl: String, ?originWindow: Window): IFrameIO {
	  return receiveWhile(function(d) return true.withEffect(function(_) { f(d); }), originUrl, originWindow);
	}
	
	override public function receiveWhile(f: Dynamic -> Bool, originUrl: String, ?originWindow: Window): IFrameIO {
	  var self = this;
	  
	  var domain = extractDomain(originUrl);
	  
	  var r = if (receivers.exists(domain)) receivers.get(domain) else [].withEffect(function(r){ self.receivers.set(domain, r); });
	  
	  var wrapper: Dynamic -> Void = null;
	  
	  wrapper = function(d: Dynamic): Void { if (!f(d)) r.remove(wrapper); }
	  
	  r.push(wrapper);
	  
	  // We need to keep track of which window is associated with this url, so in
	  // case we lose some fragments from this url, we know how to request them:
	  originUrlToWindow.set(originUrl, originWindow);
	  
	  startReceiver();
	  
	  return this;
	}
	
	override public function send(data: Dynamic, to_: String, iframe: Window): IFrameIO {
	  var from = normalize(bindTarget.location.href);
	  var to   = normalize(to_);
	  
	  var maxFragSize = 1500 - to.length;
	  var fragmentId  = 1;
	  var fragments   = Json.encodeObject(data).chunk(maxFragSize);
	  
	  var encoded = fragments.mapTo(newFragmentsList(), function(chunk): Tuple2<Window, AddressableFragment> return iframe.entuple(cast {
	    type:           'delivery',
      from:           from,
      to:             to,
      messageId:      lastMessageId.toString(),
      fragmentId:     (fragmentId++).toString(),
      fragmentCount:  fragments.size.toString(),
      data:           chunk
	  }));
	  
	  fragmentsToSend = fragmentsToSend.concat(encoded);
	  
	  ++lastMessageId;
	  
	  startSender();
	  
	  return this;
	}
	
	/** Stops the IO.
	 */
	public function stop(): IFrameIO {
	  stopSender();
	  stopReceiver();
	  
	  return this;
	}
	
	private static function normalizeOpt(url: Url): Option<Url> {
    return url.toParsedUrl().map(function(p) return p.withoutHash().toUrl());
  }
  
  private static function normalize(url: Url): Url {
    return normalizeOpt(url).getOrElseC(url);
  }
	
	private function sender(): Void {
	  switch (fragmentsToSend.headOption) {
	    case None:
	      stopSender();
	    
	    case Some(tuple): 
	      fragmentsToSend = fragmentsToSend.drop(1);
	      
	      var window   = tuple._1;
	      var fragment = tuple._2;
	      
	      // Send this chunk via the hash tag:	      
	      window.location.href = fragment.to + '#' + fragment.toMap().toQueryString().substr(1);
	  }
	}
	
	private function receiver(): Void {
	  var hash = bindTarget.location.hash;
	  
	  if (hash.length > 1) {
	    var query = '?' + hash.substr(1);
	    
	    var unknown: Dynamic = query.toQueryParameters();
	    
	    if (unknown.type == 'delivery') {
	      var packet: FragmentDelivery = cast unknown;
	      
	      var messageKey = messageKeyFrom(packet);
	      
	      var fragments = fragmentsReceivedFor(messageKey);
	      
	      var alreadyReceived = fragments.foldl(false, function(b, f) return b || f.fragmentId == packet.fragmentId);
	      
	      if (!alreadyReceived) {
	        fragments.push(packet);
	      
  	      analyzeReceivedFragments(messageKey, fragments);
  	    }
	    }
	    else if (unknown.type == 'request') {
	      var packet: FragmentRequest = cast unknown;
	      
	      var messageKey = messageKeyFrom(packet);
	      
	      
	    }
	    else if (unknown.type == 'receipt') {
	      var packet: FragmentReceipt = cast unknown;
	      
	      var messageKey = messageKeyFrom(packet);
	      
	      
	    }
	    
	    // Don't want to receive this chunk again:
	    bindTarget.location.hash = '#';
	  }
	  else {
	    var self = this;
	    
	    // We did not receive a chunk, so let's look for missing fragments:
	    var fragmentRequests = findMissingFragments();
	    
	    if (fragmentRequests.size > 0) {
	      var encoded: List<Tuple2<Window, AddressableFragment>> = fragmentRequests.flatMapTo(List.nil(), function(request: AddressableFragment): List<Tuple2<Window, AddressableFragment>> {
  	      var window = self.originUrlToWindow.get(request.to);
	      
  	      return if (window != null) {
  	        List.nil().cons(window.entuple(request));
  	      }
  	      else {
  	        List.nil();
  	      }
  	    });
	    
  	    fragmentsToSend = fragmentsToSend.concat(encoded);
  	  }
	  }
	}
	
	private function extractDomain(url: Url): String {
	  return switch (url.toParsedUrl()) {
	    case Some(parsed): parsed.hostname + parsed.pathname;
	    
	    case None: url;
	  }
	}
	
	private function analyzeReceivedFragments(messageKey: MessageKey, fragments: Array<FragmentDelivery>): Void {
	  if (fragments.length >= messageKey.fragmentCount) {
      // All fragments received -- we can send data to listeners:
      fragments.sort(function(a, b) return a.fragmentId.toInt() - b.fragmentId.toInt());
      
      var fullData = fragments.foldl('', function(a, b) return a + b.data);
    
      var message = Json.decodeObject(fullData);
    
      var domain = extractDomain(fragments[0].from);
    
      if (receivers.exists(domain)) {
        receivers.get(domain).foreach(function(r) r(message));
      }
    
      fragmentsReceived.removeByKey(messageKey);
    }
	}
	
	private function findMissingFragments(): List<AddressableFragment> {
	  return fragmentsReceived.values().foldl(List.nil(), function(allMissing, fragments) {
	    var firstFrag = fragments[0];
	    
	    fragments.sort(function(a, b) return a.fragmentId.toInt() - b.fragmentId.toInt());
	    
	    //trace('length = ' + fragments.length);
	    
	    return fragments.toList().gaps(
	      function(a, b) {
	        var lastId = a.fragmentId.toInt();
	        var curId  = b.fragmentId.toInt();
	        
	        //trace('lastId = ' + lastId + ', curId = ' + curId);
	        
	        return (lastId + 1).until(curId).map(function(missingId): AddressableFragment {
	          var request: FragmentRequest = {
    	        type:           'request',
              from:           firstFrag.to,
              to:             firstFrag.from,
              messageId:      firstFrag.messageId,
              fragmentCount:  firstFrag.fragmentCount,
              fragmentId:     missingId.toString()
    	      }
    	      
	          return request;
    	    }).toList();
	      }
	    );
	  });
	}
	
	private function fragmentsReceivedFor(messageKey: MessageKey): Array<FragmentDelivery> {
	  if (!fragmentsReceived.containsKey(messageKey)) {
      fragmentsReceived = fragmentsReceived.set(messageKey, []);
    }
        
    return fragmentsReceived.get(messageKey).get();
	}
	
	private static function messageKeyFrom(o: {messageId: String, from: String, to: String, fragmentCount: String}): MessageKey {
	  return new MessageKey(o.messageId.toInt(), o.from, o.to, o.fragmentCount.toInt());
	}
	
	private function startSender(): Void {
	  if (senderFuture.isEmpty()) {	  
	    senderFuture = Some(executor.forever(sender, 20));
	  }
	}
	
	private function stopSender(): Void {
	  senderFuture.map(function(s) { s.cancel(); return Unit; });
	  
	  senderFuture = None;
	}
	
	private function startReceiver(): Void {
	  if (receiverFuture.isEmpty()) {	  
	    receiverFuture = Some(executor.forever(receiver, 10));
	  }
	}
	
	private function stopReceiver(): Void {
	  receiverFuture.map(function(r) { r.cancel(); return Unit; });
	  
	  receiverFuture = None;
	}
}

private class MessageKey {
  public static function HasherT(): Hasher<MessageKey> {
    var intHasher = Int.HasherT();
    var stringHasher = String.HasherT();
    
    return HasherTypeclass.create({
      hash: function(v: MessageKey) {
        return intHasher.hash(v.messageId) * 
               stringHasher.hash(v.from) * 
               stringHasher.hash(v.to) *
               intHasher.hash(v.fragmentCount);
      }
    });
  }
  public static function EqualT(): Equal<MessageKey> {
    return EqualTypeclass.create({
      equal: function(v1: MessageKey, v2: MessageKey) {
        return v1.messageId  == v2.messageId && 
               v1.from       == v2.from &&
               v1.to         == v2.to &&
               v1.fragmentCount == v2.fragmentCount;
      }
    });
  }
  
  public var messageId     (default, null): Int;
  public var from          (default, null): String;
  public var to            (default, null): String;
  public var fragmentCount (default, null): Int;
  
  public function new(messageId: Int, from: String, to: String, fragmentCount: Int) {
    this.messageId = messageId;
    this.from = from;
    this.to = to;
    this.fragmentCount = fragmentCount;
  }
}

private typedef AddressableFragment = {
  to: String
}

private typedef FragmentDelivery = {>AddressableFragment,
  type:           String,
  from:           String,
  messageId:      String,
  fragmentCount:  String,
  fragmentId:     String,
  data:           String
}

private typedef FragmentRequest = {>AddressableFragment,
  type:           String,
  from:           String,
  messageId:      String,
  fragmentCount:  String,
  fragmentId:     String
}

private typedef FragmentReceipt = {>AddressableFragment,
  type:           String,
  from:           String,
  messageId:      String,
  fragmentCount:  String,
  fragmentId:     String
}