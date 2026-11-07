module BattlePopupMessages
  OPTIONS={enabled:true,effectiveness:true,critical:true,immune:true,miss:true,stats:true}
  STYLE={font:nil,language: :auto,duration:1.2,fade:0.25,rise:28}
  FOLDER='Graphics/UI/BattlePopups/'
  LABELS={
    super_effective:['Super effective!','Sehr effektiv!'],
    resisted:['Not very effective','Nicht sehr effektiv'],
    critical:['Critical hit!','Volltreffer!'],
    immune:['Immune','Immun'],miss:['Missed','Daneben']
  }
  STAT_LABELS={ATTACK:['Atk','Ang'],DEFENSE:['Def','Vert'],SPECIAL_ATTACK:['Sp. Atk','Sp.-Ang.'],
    SPECIAL_DEFENSE:['Sp. Def','Sp.-Vert.'],SPEED:['Spe','Init'],ACCURACY:['Acc','Gen'],EVASION:['Eva','Fluchtw.']}

  def self.german?
    return STYLE[:language]==:de unless STYLE[:language]==:auto
    if respond_to?(:pbGetSelectedLanguage,true)
      return pbGetSelectedLanguage.to_s.downcase.match?(/deutsch|german|\Ade\z/)
    end
    if defined?(Settings::LANGUAGES) && $PokemonSystem
      language=Settings::LANGUAGES[$PokemonSystem.language]
      return language && language.first.to_s.downcase.match?(/deutsch|german/)
    end
    false
  end

  def self.label(kind)
    LABELS.fetch(kind)[german? ? 1 : 0]
  end

  def self.emit(battle,index,kind,text=nil)
    key={super_effective: :effectiveness,resisted: :effectiveness,stat: :stats}.fetch(kind,kind)
    return false unless OPTIONS[:enabled] && OPTIONS[key]
    scene=battle.scene
    return false unless scene.respond_to?(:bpm_enqueue)
    scene.bpm_enqueue(index,kind,text || label(kind))
  end

  def self.critical_messages(user,target)
    messages=[_INTL('A critical hit!'),_INTL('A critical hit on {1}!',target.pbThis(true)),
      _INTL('{1} landed a critical hit, wishing to be praised!',user.pbThis),
      _INTL('{1} landed a critical hit on {2}, wishing to be praised!',user.pbThis,target.pbThis(true))]
    if Battle::Scene.const_defined?(:MESSAGE_BASE_CRITICAL_COLOR)
      color=Battle::Scene::MESSAGE_BASE_CRITICAL_COLOR.to_rgb24+','+Battle::Scene::MESSAGE_SHADOW_CRITICAL_COLOR.to_rgb24
      messages.concat([_INTL('<c3={1}>A critical hit!</c3>',color),
        _INTL('<c3={1}>A critical hit</c3> on {2}!',color,target.pbThis(true)),
        _INTL('{1} <c3={2}>landed a critical hit</c3>, wishing to be praised!',user.pbThis,color),
        _INTL('{1} <c3={2}>landed a critical hit</c3> on {3}, wishing to be praised!',user.pbThis,color,target.pbThis(true))])
    end
    messages
  end

  module Messages
    def bpm_filter_messages(messages)
      previous=@bpm_suppressed
      @bpm_suppressed=Array(previous)+messages
      yield
    ensure
      @bpm_suppressed=previous
    end

    def pbDisplay(message,*args,&block)
      return if @bpm_suppressed&.include?(message)
      super
    end
  end

  module Moves
    def pbEffectivenessMessage(user,target,*args)
      return super if is_a?(Battle::Move::FixedDamageMove) || target.damageState.disguise || target.damageState.iceFace
      modifier=target.damageState.typeMod
      kind=Effectiveness.super_effective?(modifier) ? :super_effective : Effectiveness.not_very_effective?(modifier) ? :resisted : nil
      return if kind && BattlePopupMessages.emit(@battle,target.index,kind)
      super
    end

    def pbHitEffectivenessMessages(user,target,*args)
      if target.damageState.critical && !target.damageState.disguise && !target.damageState.iceFace &&
         BattlePopupMessages.emit(@battle,target.index,:critical)
        @battle.bpm_filter_messages(BattlePopupMessages.critical_messages(user,target)) { super }
      else
        super
      end
    end
  end

  module Battlers
    def pbMissMessage(move,user,target)
      messages=[_INTL('{1} avoided the move in time with your shout!',target.pbThis),
        _INTL('{1} avoided the attack!',target.pbThis),_INTL("{1}'s attack missed!",user.pbThis)]
      if BattlePopupMessages.emit(@battle,target.index,:miss)
        @battle.bpm_filter_messages(messages) { super }
      else
        super
      end
    end

    def pbSuccessCheckAgainstTarget(move,user,target,targets)
      message=_INTL("It doesn't affect {1}...",target.pbThis(true))
      @battle.bpm_immunity_context(target.index,message) { super }
    end

    def pbRaiseStatStageBasic(stat,increment,*args)
      bpm_stat_change(stat) { super }
    end

    def pbLowerStatStageBasic(stat,increment,*args)
      bpm_stat_change(stat) { super }
    end

    def bpm_stat_change(stat)
      before=@stages[stat]
      depth=@bpm_stat_depth || 0
      @bpm_stat_depth=depth+1
      result=yield
      change=@stages[stat]-before
      if depth==0 && change!=0
        names=BattlePopupMessages::STAT_LABELS[stat]
        name=names ? names[BattlePopupMessages.german? ? 1 : 0] : GameData::Stat.get(stat).name_brief
        BattlePopupMessages.emit(@battle,index,:stat,"#{name} #{change>0 ? '+' : ''}#{change}")
      end
      result
    ensure
      @bpm_stat_depth=depth
    end
  end

  module ImmunityMessages
    def bpm_immunity_context(index,message)
      previous=@bpm_immunity
      @bpm_immunity=[index,message]
      yield
    ensure
      @bpm_immunity=previous
    end

    def pbDisplay(message,*args,&block)
      if @bpm_immunity && message==@bpm_immunity[1] && BattlePopupMessages.emit(self,@bpm_immunity[0],:immune)
        return
      end
      super
    end
  end

  class Popup < Sprite
    attr_reader :index,:started

    def initialize(scene,index,kind,text,viewport)
      super(viewport)
      @scene=scene;@index=index
      frame=kind==:critical ? 'critical' : kind==:stat ? 'stat' : 'normal'
      path=FOLDER+frame
      resolved=pbResolveBitmap(path)
      if resolved
        source=AnimatedBitmap.new(resolved)
        self.bitmap=Bitmap.new(source.bitmap.width,source.bitmap.height)
        bitmap.blt(0,0,source.bitmap,source.bitmap.rect)
        source.dispose
      else
        self.bitmap=Bitmap.new(120,22)
        bitmap.fill_rect(0,0,120,22,Color.new(16,23,35,230))
      end
      pbSetSystemFont(bitmap)
      bitmap.font.name=STYLE[:font] if STYLE[:font]
      bitmap.font.size=10;bitmap.font.bold=false
      bitmap.font.shadow=false if bitmap.font.respond_to?(:shadow=)
      bitmap.font.outline=false if bitmap.font.respond_to?(:outline=)
      color={super_effective:[132,230,153],resisted:[238,192,128],critical:[243,220,164],immune:[222,156,156]}.fetch(kind,[243,240,231])
      bitmap.font.color=Color.new(*color)
      bitmap.font.size-=1 while bitmap.font.size>7 && bitmap.text_size(text).width>bitmap.width-8
      if bitmap.respond_to?(:mkxp_draw_text)
        bitmap.mkxp_draw_text(4,0,bitmap.width-8,bitmap.height,text,1)
      else
        bitmap.draw_text(4,0,bitmap.width-8,bitmap.height,text,1)
      end
      self.z=150
      @started=System.uptime
      update
    end

    def update
      return if disposed?
      elapsed=System.uptime-@started
      if elapsed>=STYLE[:duration]
        dispose
        return
      end
      anchor=@scene.bpm_anchor(@index)
      @anchor=anchor if anchor
      if @anchor
        self.x=(@anchor[0]-bitmap.width/2).clamp(0,Graphics.width-bitmap.width)
        self.y=(@anchor[1]-bitmap.height/2-elapsed*STYLE[:rise]).clamp(8,Graphics.height-bitmap.height-2)
      end
      self.opacity=(255*[(STYLE[:duration]-elapsed)/STYLE[:fade],1].min).round
    end

    def dispose
      return if disposed?
      bitmap.dispose if bitmap && !bitmap.disposed?
      super
    end
  end

  module Scene
    def bpm_enqueue(index,kind,text)
      return false unless @sprites && @sprites["pokemon_#{index}"] && @viewport
      @bpm_queue||={};@bpm_active||={}
      @bpm_queue[index]||=[]
      return false if @bpm_queue[index].length>=8
      @bpm_queue[index] << [kind,text]
      true
    end

    def bpm_anchor(index)
      actor=@sprites["pokemon_#{index}"]
      return nil unless actor && !actor.disposed? && actor.visible
      if respond_to?(:sc_stage_sprite_bounds)
        left,top,right,bottom=sc_stage_sprite_bounds(actor,index)
        left,right=actor.src_rect.width-right,actor.src_rect.width-left if actor.sprite.mirror
        return [actor.x+((left+right)/2.0-actor.ox)*actor.zoom_x,actor.y+((top+bottom)/2.0-actor.oy)*actor.zoom_y]
      end
      [actor.x+(actor.src_rect.width/2.0-actor.ox)*actor.zoom_x,actor.y+(actor.src_rect.height/2.0-actor.oy)*actor.zoom_y]
    end

    def bpm_update
      return unless @bpm_queue
      @bpm_queue.each_pair do |index,queue|
        active=@bpm_active[index]
        active.update if active && !active.disposed?
        next if active && !active.disposed?
        @bpm_active.delete(index)
        next if queue.empty?
        kind,text=queue.shift
        @bpm_active[index]=Popup.new(self,index,kind,text,@viewport)
      end
    end

    def pbGraphicsUpdate(*args)
      super
      bpm_update
    end

    def bpm_dispose
      @bpm_active&.each_value { |sprite| sprite.dispose }
      @bpm_active={};@bpm_queue={}
    end

    def pbDisposeSprites(*args)
      bpm_dispose
      super
    end

    def pbEndBattle(*args)
      super
    ensure
      bpm_dispose
    end
  end

  module EBDXScene
    def animateScene(*args,&block)
      super
      bpm_update
    end
  end
end

Battle.prepend(BattlePopupMessages::Messages)
Battle.prepend(BattlePopupMessages::ImmunityMessages)
Battle::Move.prepend(BattlePopupMessages::Moves)
Battle::Battler.prepend(BattlePopupMessages::Battlers)
Battle::Scene.prepend(BattlePopupMessages::Scene)
Battle::Scene.prepend(BattlePopupMessages::EBDXScene) if Battle::Scene.method_defined?(:animateScene)
