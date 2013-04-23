/**
 * Created with IntelliJ IDEA.
 * User: Женя
 * Date: 09.04.13
 * Time: 12:40
 */
package components.objects.connection.model
{
	import components.communication.event.CommunicationModelEvent;
	import components.communication.model.CommunicationsModel;
	import components.communication.vo.ICommunicationVO;
	import components.map.event.MapModelEvent;
	import components.map.model.MapModel;
	import components.map.vo.RawVO;
	import components.objects.connection.util.CommunicationAreaUtil;
	import components.objects.interfaces.ICommunicationConsumer;
	import components.tools.event.ToolsStateModelEvent;
	import components.tools.model.ToolsStateModel;
	import components.tools.types.ToolStateTypes;

	import flash.geom.Rectangle;

	import ru.drimmi.geom.Pt;

	import stream.QuestEventsStream;

	/**
	 * Модель связей объектов по коммуникациям.
	 * При рассчете оперирует типами коммуникаций (CommunicationItemDescriptor.type)
	 */
	public class CommunicationConnectionModel
	{
		private var mainObjects:Vector.<ICommunicationConsumer> = new <ICommunicationConsumer>[];
		private var mainAreaIndexes:Object = {}; // карта главных областей коммуникаций: <communicationType> = Vector.<uint> - вектор индексов областей коммуникаций
		private var isCommunicationsChanged:Boolean;

		private var areaUtil:CommunicationAreaUtil;

		private var mapModel:MapModel;
		private var communicationsModel:CommunicationsModel;

		public function CommunicationConnectionModel(communicationsModel:CommunicationsModel, mapModel:MapModel, toolsStateModel:ToolsStateModel)
		{
			this.communicationsModel = communicationsModel;
			this.mapModel = mapModel;

			areaUtil = new CommunicationAreaUtil();
//            следим за объектами
			this.mapModel.addEventListener(MapModelEvent.OBJECT_SOLID_ADDED, onObjectSolidAdded);
			this.mapModel.addEventListener(MapModelEvent.OBJECT_REMOVING, onObjectRemoving);
			this.mapModel.addEventListener(MapModelEvent.OBJECT_MOVED, onObjectMoved);
//            следим за коммуникациями
			this.communicationsModel.addEventListener(CommunicationModelEvent.COMMUNICATION_TILE_ADD, onCommunicationsChange);
			this.communicationsModel.addEventListener(CommunicationModelEvent.COMMUNICATION_TILE_REMOVE, onCommunicationsChange);
			this.communicationsModel.addEventListener(CommunicationModelEvent.COMMUNICATIONS_TILES_UPDATED, onCommunicationsModelUpdated);
//            следим за инструментами
			toolsStateModel.addEventListener(ToolsStateModelEvent.TOOL_STATE_CHANGED, onToolStateChanged, false, -1);
		}

		public function cleanup():void
		{
			mainObjects.splice(0, mainObjects.length);
			cleanMainAreaIndexes();

			super.cleanup();
		}

		private function onObjectSolidAdded(event:MapModelEvent):void
		{
			var obj:ICommunicationConsumer = event.obj as ICommunicationConsumer;
			if (obj)
			{
				if (isMainObject(obj))
				{
					mainObjects.push(obj);
					updateMainAreaIndexes();
					updateCommunicationConsumersAvailability();
				}
				else if (obj.needUnavailableCommunication)
				{
					changeCommunicationConsumerAvailability(obj);
				}
			}
		}

		private function onObjectRemoving(event:MapModelEvent):void
		{
			var obj:ICommunicationConsumer = event.obj as ICommunicationConsumer;
			if (obj)
			{
				if (isMainObject(obj) && mainObjects.indexOf(obj) > -1)
				{
					mainObjects.splice(mainObjects.indexOf(obj), 1);
					updateMainAreaIndexes();
					updateCommunicationConsumersAvailability();
				}
			}
		}

		private function onObjectMoved(event:MapModelEvent):void
		{
			var obj:ICommunicationConsumer = event.obj as ICommunicationConsumer;
			if (obj)
			{
				if (isMainObject(obj))
				{
					updateMainAreaIndexes();
					updateCommunicationConsumersAvailability();
				}
				else
				{
					changeCommunicationConsumerAvailability(obj);
				}
			}
		}

		private function onCommunicationsChange(event:CommunicationModelEvent):void
		{
			isCommunicationsChanged = true;
		}

		private function onCommunicationsModelUpdated(event:CommunicationModelEvent):void
		{
			isCommunicationsChanged = true;
			connectionsUpdate();
		}

		private function onToolStateChanged(event:ToolsStateModelEvent):void
		{
			if (event.newState == ToolStateTypes.NEUTRAL_STATE || event.newState == ToolStateTypes.FRIEND_LOCATION_STATE)
			{
				connectionsUpdate();
			}
		}

		private function connectionsUpdate():void
		{
			if (isCommunicationsChanged)
			{
				areaUtil.updateCommunicationAreaIndexes(communicationsModel.communicationsVector);
				updateMainAreaIndexes();
				updateCommunicationConsumersAvailability();
				isCommunicationsChanged = false;
			}
		}

		private function updateMainAreaIndexes():void
		{
			cleanMainAreaIndexes();
			for each(var mainObject:ICommunicationConsumer in mainObjects)
			{
				addMainAreaIndexesNearCommunications(mainObject);
			}
		}

		private function cleanMainAreaIndexes():void
		{
			for (var key:String in mainAreaIndexes)
			{
				delete mainAreaIndexes[key];
			}
		}

		private function addMainAreaIndexesNearCommunications(mainObject:ICommunicationConsumer):void
		{
			var pos:Pt = new Pt();
			var objectRect:Rectangle = new Rectangle(mainObject.x, mainObject.y, mainObject.width, mainObject.length);

			var i:int;
			//проходимся по x периметру
			for (i = objectRect.x; i < objectRect.right; i++)
			{
				pos.x = i;
				pos.y = objectRect.y - 1;
				addMainAreaIndex(mainObject, pos);

				pos.y = objectRect.bottom;
				addMainAreaIndex(mainObject, pos);
			}

			//проходимся по y периметру
			for (i = objectRect.y; i < objectRect.bottom; i++)
			{
				pos.x = objectRect.x - 1;
				pos.y = i;
				addMainAreaIndex(mainObject, pos);

				pos.x = objectRect.right;
				addMainAreaIndex(mainObject, pos);
			}
		}

		private function addMainAreaIndex(mainObject:ICommunicationConsumer, pt:Pt):void
		{
			var communication:ICommunicationVO = communicationsModel.getCommunication(pt);
			if (communication && isMainObject(mainObject))
			{
				var areaIndexes:Vector.<uint> = getMainAreaIndexes(communication.type);
				var communicationArea:uint = areaUtil.getAreaIndex(communication);
				if (areaIndexes.indexOf(communicationArea) == -1)
				{
					areaIndexes.push(communicationArea);
				}
			}
		}

		private function getMainAreaIndexes(communicationType:uint):Vector.<uint>
		{
			if (!(communicationType in mainAreaIndexes))
			{
				mainAreaIndexes[communicationType] = new Vector.<uint>;
			}
			return mainAreaIndexes[communicationType];
		}

		private function updateCommunicationConsumersAvailability():void
		{
			for each (var obj:RawVO in mapModel.objects)
			{
				var communicationConsumer:ICommunicationConsumer = obj as ICommunicationConsumer;
				if (communicationConsumer)
				{
					changeCommunicationConsumerAvailability(communicationConsumer);
				}
			}
		}

		private function changeCommunicationConsumerAvailability(obj:ICommunicationConsumer):void
		{
			if (obj.requiredCommunicationsTypes.length > 0)
			{
				var pos:Pt = new Pt();
				var i:int;

				var availableCommunicationTypes:Vector.<uint> = new <uint>[];
				var nearCommunicationTypes:Vector.<uint> = new <uint>[];

				//проходимся по x периметру
				for (i = obj.x; i < (obj.x + obj.width); i++)
				{
					pos.x = i;
					pos.y = obj.y - 1;
					addAvailableAndNearCommunicationThroughPt(obj, pos, availableCommunicationTypes, nearCommunicationTypes);

					pos.y = obj.y + obj.length;
					addAvailableAndNearCommunicationThroughPt(obj, pos, availableCommunicationTypes, nearCommunicationTypes);
				}

				//проходимся по y периметру
				for (i = obj.y; i < (obj.y + obj.length); i++)
				{
					pos.x = obj.x - 1;
					pos.y = i;
					addAvailableAndNearCommunicationThroughPt(obj, pos, availableCommunicationTypes, nearCommunicationTypes);

					pos.x = obj.x + obj.width;
					addAvailableAndNearCommunicationThroughPt(obj, pos, availableCommunicationTypes, nearCommunicationTypes);
				}

				for each (var communicationType:uint in obj.requiredCommunicationsTypes)
				{
					var isAvailable:Boolean = (availableCommunicationTypes.indexOf(communicationType) > -1);
					obj.setAvailableCommunication(communicationType, isAvailable);
					if (isAvailable)
					{
						QuestEventsStream.objectConnectionToMainCommunicationChange(obj, communicationType);
					}

					var isNear:Boolean = (nearCommunicationTypes.indexOf(communicationType) > -1);
					obj.setNearCommunication(communicationType, isNear);
				}
			}
		}

		private function addAvailableAndNearCommunicationThroughPt(obj:ICommunicationConsumer, pt:Pt, availableCommunicationTypes:Vector.<uint>, nearCommunicationTypes:Vector.<uint>):void
		{
			var communication:ICommunicationVO = communicationsModel.getCommunication(pt);
			if (communication && (obj.requiredCommunicationsTypes.indexOf(communication.type) > -1))
			{
				if (nearCommunicationTypes.indexOf(communication.type) == -1)
				{
					nearCommunicationTypes.push(communication.type);
				}
				if (hasSimilarHomeAreaIndex(communication) && (availableCommunicationTypes.indexOf(communication.type) == -1))
				{
					availableCommunicationTypes.push(communication.type);
				}
			}
		}

		private function hasSimilarHomeAreaIndex(communication:ICommunicationVO):Boolean
		{
			return communication && (getMainAreaIndexes(communication.type).indexOf(areaUtil.getAreaIndex(communication)) != -1);
		}

		private function isMainObject(obj:ICommunicationConsumer):Boolean
		{
			return (obj.communicationEmittingAbilities.length > 0);
		}


	}
}
