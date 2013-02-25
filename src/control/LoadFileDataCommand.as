package control
{
	import dragonBones.objects.DecompressedData;
	import dragonBones.objects.XMLDataParser;
	import dragonBones.utils.BytesType;
	
	import flash.display.Bitmap;
	import flash.display.BitmapData;
	import flash.display.Loader;
	import flash.events.Event;
	import flash.events.IOErrorEvent;
	import flash.events.ProgressEvent;
	import flash.geom.Matrix;
	import flash.geom.Rectangle;
	import flash.net.FileFilter;
	import flash.net.FileReference;
	import flash.net.URLLoader;
	import flash.net.URLLoaderDataFormat;
	import flash.net.URLRequest;
	import flash.system.LoaderContext;
	import flash.utils.ByteArray;
	
	import message.MessageDispatcher;
	
	import model.SkeletonXMLProxy;
	
	import utils.GlobalConstValues;
	import utils.PNGEncoder;
	
	import zero.zip.Zip;
	import zero.zip.ZipFile;

	public class LoadFileDataCommand
	{
		public static const instance:LoadFileDataCommand = new LoadFileDataCommand();
		
		private static const FILE_FILTER_ARRAY:Array = [new FileFilter("Exported data", "*." + String(["swf", "png", "zip"]).replace(/\,/g, ";*."))];
		private static var _helpMatirx:Matrix = new Matrix();
		
		private var _fileREF:FileReference;
		private var _urlLoader:URLLoader;
		private var _loaderContext:LoaderContext;
		
		private var _skeletonXMLProxy:SkeletonXMLProxy;
		private var _bitmapData:BitmapData;
		
		private var _isLoading:Boolean;
		public function isLoading():Boolean
		{
			return _isLoading;
		}
		
		public function LoadFileDataCommand()
		{
			_fileREF = new FileReference();
			_urlLoader = new URLLoader();
			_loaderContext = new LoaderContext(false)
			_loaderContext.allowCodeImport = true;
		}
		
		public function load(url:String = null):void
		{
			if(_isLoading)
			{
				return;
			}
			if(url)
			{
				_isLoading = true;
				MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA);
				_urlLoader.addEventListener(IOErrorEvent.IO_ERROR, onURLLoaderHandler);
				_urlLoader.addEventListener(ProgressEvent.PROGRESS, onURLLoaderHandler);
				_urlLoader.addEventListener(Event.COMPLETE, onURLLoaderHandler);
				_urlLoader.dataFormat = URLLoaderDataFormat.BINARY;
				_urlLoader.load(new URLRequest(url));
			}
			else
			{
				_fileREF.addEventListener(Event.SELECT, onFileHaneler);
				_fileREF.browse(FILE_FILTER_ARRAY);
			}
		}
	
		private function onURLLoaderHandler(e:Event):void
		{
			switch(e.type)
			{
				case IOErrorEvent.IO_ERROR:
					_urlLoader.removeEventListener(Event.COMPLETE, onURLLoaderHandler);
					_urlLoader.removeEventListener(IOErrorEvent.IO_ERROR, onURLLoaderHandler);
					_urlLoader.removeEventListener(ProgressEvent.PROGRESS, onURLLoaderHandler);
					_isLoading = false;
					MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA_ERROR);
					break;
				case ProgressEvent.PROGRESS:
					var progressEvent:ProgressEvent = e as ProgressEvent;
					MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA_PROGRESS, progressEvent.bytesLoaded / progressEvent.bytesTotal );
					break;
				case Event.COMPLETE:
					_urlLoader.removeEventListener(Event.COMPLETE, onURLLoaderHandler);
					_urlLoader.removeEventListener(IOErrorEvent.IO_ERROR, onURLLoaderHandler);
					_urlLoader.removeEventListener(ProgressEvent.PROGRESS, onURLLoaderHandler);
					setData(e.target.data);
					break;
			}
		}
		
		private function onFileHaneler(e:Event):void
		{
			switch(e.type)
			{
				case Event.SELECT:
					_isLoading = true;
					MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA);
					_fileREF.removeEventListener(Event.SELECT, onFileHaneler);
					_fileREF.addEventListener(Event.COMPLETE, onFileHaneler);
					_fileREF.load();
					break;
				case Event.COMPLETE:
					_fileREF.removeEventListener(Event.COMPLETE, onFileHaneler);
					setData(_fileREF.data);
					break;
			}
		}
		
		private function setData(fileData:ByteArray):void
		{
			_isLoading = false;
			var dataType:String = BytesType.getType(fileData);
			switch(dataType)
			{
				case BytesType.SWF:
				case BytesType.PNG:
				case BytesType.JPG:
					try
					{
						var decompressedData:DecompressedData = XMLDataParser.decompressData(fileData);
						_skeletonXMLProxy = new SkeletonXMLProxy();
						_skeletonXMLProxy.skeletonXML = decompressedData.skeletonXML;
						_skeletonXMLProxy.textureAtlasXML = decompressedData.textureAtlasXML;
						
						MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA_COMPLETE, _skeletonXMLProxy, decompressedData.textureBytes);
						return;
					}
					catch(_e:Error)
					{
						break;
					}
				case BytesType.ZIP:
					try
					{
						var images:Object;
						var zip:Zip = new Zip();
						zip.decode(fileData);
						_skeletonXMLProxy = new SkeletonXMLProxy();
						
						for each(var zipFile:ZipFile in zip.fileV)
						{
							if(!zipFile.isDirectory)
							{
								
								if(zipFile.name == GlobalConstValues.SKELETON_XML_NAME)
								{
									_skeletonXMLProxy.skeletonXML = XML(zipFile.data);
								}
								else if(zipFile.name == GlobalConstValues.TEXTURE_ATLAS_XML_NAME)
								{
									_skeletonXMLProxy.textureAtlasXML = XML(zipFile.data);
								}
								else if(zipFile.name.indexOf(GlobalConstValues.TEXTURE_NAME) == 0)
								{
									if(zipFile.name.indexOf("/") > 0)
									{
										var name:String = zipFile.name.replace(/\.\w+$/,"");
										name = name.split("/").pop();
										if(!images)
										{
											images = {};
										}
										images[name] = zipFile.data;
									}
									else
									{
										var textureBytes:ByteArray = zipFile.data;
									}
								}
							}
						}
						zip.clear();
						if(textureBytes)
						{
							//_textureBytes
							MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA_COMPLETE, _skeletonXMLProxy, textureBytes);
							return;
						}
						else if(images)
						{
							spliceBitmapData(images);
							return;
						}
						break;
					}
					catch(_e:Error)
					{
						break;
					}
				default:
					break;
			}
			MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA_ERROR);
		}
		
		private var _images:Object;
		private var _imageName:String;
		
		private function spliceBitmapData(images:Object):void
		{
			_images = images;
			_bitmapData = new BitmapData(
				_skeletonXMLProxy.textureAtlasWidth,
				_skeletonXMLProxy.textureAtlasHeight,
				true,
				0xFF00FF
			);
			
			spliceBitmapDataStep(null);
		}
		
		private function spliceBitmapDataStep(e:Event):void
		{
			if(e)
			{
				e.target.removeEventListener(Event.COMPLETE, spliceBitmapDataStep);
				var bitmap:Bitmap = e.target.content as Bitmap;
				var rect:Rectangle = _skeletonXMLProxy.getSubTextureRect(_imageName);
				if(rect)
				{
					_helpMatirx.tx = rect.x;
					_helpMatirx.ty = rect.y;
					_bitmapData.draw(bitmap.bitmapData, _helpMatirx, null, null, rect);
				}
			}
			for (var name:String in _images)
			{
				var imageBytes:ByteArray = _images[name];
				_imageName = name;
				delete _images[_imageName];
				break;
			}
			if(!imageBytes)
			{
				MessageDispatcher.dispatchEvent(MessageDispatcher.LOAD_FILEDATA_COMPLETE, _skeletonXMLProxy, PNGEncoder.encode(_bitmapData));
				return;
			}
			var loader:Loader = new Loader();
			loader.contentLoaderInfo.addEventListener(Event.COMPLETE, spliceBitmapDataStep);
			loader.loadBytes(imageBytes, _loaderContext);
		}
	}
}