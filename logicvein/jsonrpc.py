### ---------------------------------------------------------------------------
### You can copy the code below into any python script that needs to interact
### with the Net LineDancer JSON-RPC 2.0 API

import sys
import ssl
import json
import time
import random
import urllib
import urllib.request
import urllib.error
import urllib.parse
import http.cookiejar
import functools
from hashlib import sha1
from datetime import tzinfo

class JsonRpcProxy(object):
   '''A class implementing a JSON-RPC Proxy.'''

   def __init__(self, url, username, password):
      self._url = url
      self._username = username
      self._password = password

      if (sys.version_info >= ( 2, 7, 9 )):
         ctx = ssl.create_default_context()
         ctx.check_hostname = False
         ctx.verify_mode = ssl.CERT_NONE
         self._https_handler = urllib.request.HTTPSHandler(context=ctx)
      else:
         self._https_handler = urllib.request.HTTPSHandler()

      self._cookie_processor = urllib.request.HTTPCookieProcessor(http.cookiejar.CookieJar())

      self._hasher = sha1()
      self._id = 0
      self._opener = urllib.request.build_opener(self._cookie_processor, self._https_handler)
      self._opener.add_handler(JsonRpcProcessor())

   @classmethod
   def fromHost(cls, host, username, password):
      proxy = cls("https://{0}/jsonrpc".format(host), username, password)
      proxy._host = host

      return proxy

   def _next_id(self):
      self._id += 1
      self._hasher.update(str(self._id).encode('utf-8'))
      self._hasher.update(time.ctime().encode('utf-8'))
      self._hasher.update(str(random.random).encode('utf-8'))
      return self._hasher.hexdigest()

   def call(self, method, *args, **kwargs):
      '''call a JSON-RPC method'''

      url = self._url
      if (self._id == 0):
         url = url + '?' + urllib.parse.urlencode([('j_username', self._username), ('j_password', self._password)])

      postdata = {
        'jsonrpc': '2.0',
        'method': method,
        'id': self._next_id(),
        'params': args
      }

      encoded = json.dumps(postdata).encode('utf-8')
      try:
         respdata = self._opener.open(url, encoded).read()
      except urllib.error.URLError as ex:
         print('Connection error: ' + str(ex))
         sys.exit(-1)

      jsondata = json.loads(respdata)

      if ('error' in jsondata):
         raise JsonError(jsondata['error'])

      return jsondata['result']

class JsonRpcProcessor(urllib.request.BaseHandler):
   def __init__(self):
      self.handler_order = 100

   def http_request(self, request):
      request.add_header('content-type', 'application/json')
      request.add_header('user-agent', 'jsonrpc/netld')
      return request

   https_request = http_request

class JsonError(Exception):
   def __init__(self, value):
      self.value = value
   def __str__(self):
      return repr(self.value)

def dict_encode(obj):
   items = getattr(obj, 'iteritems', obj.items)
   return dict( (encode_(k),encode_(v)) for k,v in items() )

def list_encode(obj):
   return list(encode_(i) for i in obj)

def safe_encode(obj):
   '''Always return something, even if it is useless for serialization'''
   try: json.dumps(obj)
   except TypeError: obj = str(obj)
   return obj

def encode_(obj, **kw):
   obj = getattr(obj, 'json_equivalent', lambda: obj)()
   func = lambda x: x
   if hasattr(obj, 'items'):
      func = dict_encode
   elif hasattr(obj, '__iter__'):
      func = list_encode
   else:
      func = safe_encode
   return func(obj)

encode = functools.partial(json.dumps, default=encode_)

class UTC(tzinfo):
   """UTC"""

   def utcoffset(self, dt):
      return timedelta(0)

   def tzname(self, dt):
      return "UTC"

   def dst(self, dt):
      return timedelta(0)

utc = UTC()
