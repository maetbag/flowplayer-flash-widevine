﻿package org.flowplayer.rtmp {
	import com.widevine.WvNetStream;
	import com.widevine.WvNetConnection;
	import flash.events.NetStatusEvent;
	import org.flowplayer.util.Log;
	import org.flowplayer.controller.NetStreamControllingStreamProvider;
	import org.flowplayer.model.Clip;
	import flash.events.TimerEvent;
	import flash.utils.Timer;
	import org.flowplayer.model.ClipEvent;
	import org.flowplayer.model.ClipEventType;
	import org.flowplayer.view.Flowplayer;
	import org.flowplayer.model.PluginModel;
	
	import flash.utils.setTimeout;
	
	public class WidevineNetStream extends WvNetStream {
		protected var log:Log = new Log(this);
		private var rePause:Boolean;
		private var _pauseWaitTimer:Timer;
		private var _pauseRequired:Boolean;
		private var _clip:Clip;
		private var _seeking:Boolean;
		private var _player:Flowplayer;
		
		private var _indicator:PluginModel;
		private var _indicatorTimer:Timer;

		
		public function WidevineNetStream(connection:WvNetConnection, clip:Clip, player:Flowplayer):void
		{
			super(connection);
			_clip = clip;
			_player = player;
			addEventListener(NetStatusEvent.NET_STATUS, onNetStatus);
			
			lookupWidevineIndicator();
		}
		
		private function lookupWidevineIndicator():void
		{
			_indicator = _player.pluginRegistry.getPlugin("widevineIndicator") as PluginModel;
            log.debug("lookupWidevineIndicator() " + _indicator ? "found indicator" : "indicator not present");

			_indicatorTimer = new Timer(10000, 1);
			_indicatorTimer.addEventListener(TimerEvent.TIMER, function(e:TimerEvent):void { 
				if ( _indicator )
					_player.hidePlugin(_indicator.name);
			});
		}
		
		private function showIndicator(label:String):void
		{
			if ( ! _indicator )
				return;

			_indicator.pluginObject.html = label;

			_indicatorTimer.reset();
			_player.showPlugin(_indicator.name);

			_indicatorTimer.start();
		}
		
		private function onNetStatus(event:NetStatusEvent):void {
            log.info("_onNetStatus, code: " + event.info.code + ", details: " + event.info.details + ", description: " + event.info.description + ", isPlaying: " + getPlayStatus() + ", time: " + getCurrentMediaTime() + ", bufferLength: " + bufferLength + ", buffertime: " + bufferTime + ", backBufferLength: " + backBufferLength + ", backBuffertime: " + backBufferTime);
			
			switch (event.info.code) {
				case "NetStream.Buffer.Full":
				if(rePause) {
					log.debug("repausing");
					super.pause();
					rePause = false;
				}
				if (_seeking) { 
					log.debug("Completing seek");
					_clip.dispatchEvent(new ClipEvent(ClipEventType.SEEK, getCurrentMediaTime()));
					_seeking = false;
				}
				break;
				
				// we get this near the end of a fast-forward/rewind
				case "NetStream.Play.Complete":
					log.debug("setting timeout for endOfClip");
					setTimeout(endOfClip, Math.max(100, (bufferLength)*1000));
				break;
				
				
				case "NetStream.Wv.EmmFailed":
				case "NetStream.Wv.EmmError":
				case "NetStream.Wv.EmmExpired":
				case "NetStream.Wv.DcpStop":
				case "NetStream.Wv.DcpAlert":
					showIndicator( event.info.code + ": " + event.info.details);
					break;
			}
		}
		
		private function endOfClip():void
		{
			log.debug("emitting finish, pause, and seek");
			_clip.dispatchBeforeEvent(new ClipEvent(ClipEventType.FINISH));
			super.pause();
			_clip.dispatchEvent(new ClipEvent(ClipEventType.FINISH));
		}
		
		public override function pause():void 
		{
			log.info("pause() timer started");
			
			// timer is used because flowplayer calls pause() before seeking, and then resumes after seeking
			// but widevine requires the video to be playing during a seek, so we set a timer to delay the pause()
			// so we can wait and see if flowplayer calls seek()
			if (_pauseWaitTimer && _pauseWaitTimer.running) return;
			_pauseRequired = true;
            _pauseWaitTimer = new Timer(200);
            _pauseWaitTimer.addEventListener(TimerEvent.TIMER, onPauseWait);
            _pauseWaitTimer.start();

		}
		
		public override function resume():void 
		{
			_pauseRequired = false;
			rePause = false;
			log.info("resume()");
			super.resume();
		}
		
        private function onPauseWait(event:TimerEvent):void {
			_pauseWaitTimer.stop();
            if (_pauseRequired) {
				log.info("pausing");
				super.pause();
				_pauseRequired = false;
            } else {
				log.info("pause cancelled by seek/resume");
			}
        }

		
		public override function seek(offset:Number):void 
		{
			// Ignore any recent pause() call
			_pauseRequired = false;
			
			// When buffer fills after seeking, we inform player the seek has completed
			_seeking = true;
			
			log.info("seek to " + offset + ", isPlaying " + getPlayStatus());
			// Widevine cannot seek while paused
			if (getPlayStatus()  == false) {
				log.info("paused during seek, resuming and requesting pause");
				resume();
				rePause = true;
			}
			super.seek(offset);
		}
	}
}
